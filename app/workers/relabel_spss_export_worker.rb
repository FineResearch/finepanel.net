# frozen_string_literal: true

require 'zip'

# Recibe el zip que Confirmit manda con la sintaxis SPSS (.sps + .asc) de un
# export, corrige los labels (ExportRelabeling::SpssSyntaxRewriter) y compila
# el resultado a .sav real -- el compile en si corre en una Lambda aparte
# (ver ExportRelabeling::PsppLambdaClient, lambda/pspp_compiler/), no en
# este mismo contenedor: la base de la app (Alpine 3.7) no puede instalar
# ni correr PSPP de ninguna forma (ver el diagnostico en Dockerfile.release).
#
# Un zip puede traer mas de un par .sps+.asc (los loops de la encuesta se
# exportan como archivos separados, ej. "..._def_X.sps"/"..._def_X_fichas.sps")
# -- se procesan todos los que haya, un .sav por par, sin fusionarlos.
class RelabelSpssExportWorker
  include Sidekiq::Worker
  sidekiq_options retry: 3

  WORK_ROOT = Rails.root.join('tmp', 'relabel_spss')
  # El FILE HANDLE del .sps original apunta a un path de Windows
  # (c:\temp\archivo.asc) porque Confirmit asume que alguien lo va a correr
  # a mano en SPSS local -- se reescribe para apuntar al path fijo que
  # espera la Lambda de compilado (ver ExportRelabeling::PsppLambdaClient),
  # no a un path local de este contenedor.
  FILE_HANDLE_NAME = /NAME\s*=\s*'([^']+)'/.freeze

  def perform(zip_path, project_id, recipients)
    @work_dir = WORK_ROOT.join(SecureRandom.uuid)
    FileUtils.mkdir_p(@work_dir)

    output_paths, relabeled = build_output_paths(zip_path, project_id)

    ExportDeliveryMailer.relabeled_export_email(recipients, project_id, output_paths, relabeled: relabeled).deliver_now
  ensure
    FileUtils.rm_rf(@work_dir) if @work_dir
    File.delete(zip_path) if zip_path && File.exist?(zip_path)
  end

  private

  # El proceso principal es que el cliente reciba la base -- Diego: "lo mas
  # seguro seria que si algo falla se envie lo mismo que se recibio... asi
  # cubrimos el riesgo de que los datos se enviaron aunque el formato no
  # fuera perfecto". A diferencia de Excel (que separa base + mejoras
  # opcionales), aca todo el pipeline (reescribir sintaxis + compilar con
  # PSPP) ES el producto -- no hay una version "mas simple" intermedia a la
  # que degradar, asi que cualquier fallo cae directo al zip original tal
  # cual llego. Devuelve [paths_a_adjuntar, se_pudo_reetiquetar?].
  def build_output_paths(zip_path, project_id)
    lookup = build_lookup(project_id)
    extract_zip(zip_path, @work_dir)
    sav_paths = sps_files.map { |sps_path| build_sav(sps_path, lookup) }
    [sav_paths, true]
  rescue StandardError => e
    Rails.logger.error("[RelabelSpssExportWorker] fallo el pipeline de re-etiquetado, se manda la base sin cambios: #{e.class} #{e.message}")
    [[zip_path], false]
  end

  def build_lookup(project_id)
    ExportRelabeling::ConfirmitSchemaFetcher.call(project_id)
  end

  def extract_zip(zip_path, work_dir)
    Zip::File.open(zip_path) do |zip_file|
      zip_file.each { |entry| entry.extract(work_dir.join(entry.name).to_s) }
    end
  end

  def sps_files
    Dir.glob(@work_dir.join('*.sps'))
  end

  def build_sav(sps_path, lookup)
    original = File.read(sps_path, encoding: 'bom|utf-8')
    data_path = resolve_data_file_path(original)
    raise "Falta el archivo de datos #{data_path} para #{sps_path}" unless File.exist?(data_path)

    rewritten = ExportRelabeling::SpssSyntaxRewriter.call(original, lookup: lookup)
    rewritten = rewritten.sub(FILE_HANDLE_NAME, "NAME = '#{ExportRelabeling::PsppLambdaClient::LAMBDA_DATA_PATH}'")
    rewritten += "\nSAVE OUTFILE='#{ExportRelabeling::PsppLambdaClient::LAMBDA_SAV_PATH}'.\n"

    relabeled_sps_path = sps_path.sub(/\.sps\z/, '_relabeled.sps')
    File.write(relabeled_sps_path, rewritten)

    sav_path = sps_path.sub(/\.sps\z/, '.sav')
    ExportRelabeling::PsppLambdaClient.compile(sps_path: relabeled_sps_path, data_path: data_path, output_path: sav_path)

    sav_path
  end

  def resolve_data_file_path(sps_text)
    match = FILE_HANDLE_NAME.match(sps_text)
    raise 'No se encontro FILE HANDLE NAME en la sintaxis' unless match

    original_name = File.basename(match[1].tr('\\', '/'))
    @work_dir.join(original_name).to_s
  end
end
