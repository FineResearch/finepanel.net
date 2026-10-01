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
  # Confirmit siempre cierra la sintaxis con un "LIST." suelto (una muestra
  # de los datos pensada para revision manual en SPSS de escritorio) --
  # confirmado en p833174000229_def_dcasar_586575525.sps real. Sin
  # variables especificadas, LIST imprime TODAS las columnas de TODOS los
  # casos al log -- con el .asc real de ese proyecto (5.78MB), esto hizo
  # que el log de pspp superara el limite de 6MB de respuesta sincronica
  # de Lambda. Se quita antes de compilar: no aporta nada al .sav final.
  LIST_COMMAND = /^[ \t]*LIST[ \t]*\.[ \t]*\r?\n?/i.freeze
  # Confirmit a veces exporta el .asc/.dat con un BOM UTF-8 (3 bytes) al
  # principio -- como DATA LIST FIXED lee por posicion de BYTE, esos 3
  # bytes invisibles corren TODA la primera fila hacia la derecha.
  # Confirmado contra un archivo real (p833174000229): el RESPONSEID y el
  # RESPID de la primera fila terminaban pegados dentro de otras columnas
  # (STATUS/FECHACOMPLETA), y esa fila se perdia/corrompia en el .sav
  # resultante. No se toca el .asc ORIGINAL (el fallback a "se manda la
  # base sin cambios" usa el zip tal cual llego) -- se compila una copia
  # sin el BOM.
  UTF8_BOM = "\xEF\xBB\xBF".b.freeze
  # Default de PSPP es 100 -- lo suficientemente bajo como para pisarse con
  # cualquier export real (confirmado: un archivo de 80 casos ya genera
  # >100 warnings de "VALUE LABELS: Truncating..."/formato no numerico).
  # Al pisarse, PSPP corta el procesamiento de sintaxis ("Warnings exceed
  # limit... halted") -- no se confirmo que esto perdiera casos en los
  # tests contra datos reales, pero es barato subirlo preventivamente.
  MXWARNS_DIRECTIVE = "SET MXWARNS=100000.\n"

  def perform(zip_path, project_id, recipients, project_title = nil, interview_status_filter = nil)
    @work_dir = WORK_ROOT.join(SecureRandom.uuid)
    FileUtils.mkdir_p(@work_dir)

    output_paths, relabeled = build_output_paths(zip_path, project_id)

    ExportDeliveryMailer.relabeled_export_email(
      recipients, project_id, output_paths, export_type: :spss, relabeled: relabeled,
      project_title: project_title, interview_status_filter: interview_status_filter
    ).deliver_now
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

    clean_data_path = strip_bom(data_path)

    rewritten = ExportRelabeling::SpssSyntaxRewriter.call(original, lookup: lookup)
    rewritten = rewritten.sub(FILE_HANDLE_NAME, "NAME = '#{ExportRelabeling::PsppLambdaClient::LAMBDA_DATA_PATH}'")
    rewritten = rewritten.gsub(LIST_COMMAND, '')
    rewritten = MXWARNS_DIRECTIVE + rewritten
    rewritten += "\nSAVE OUTFILE='#{ExportRelabeling::PsppLambdaClient::LAMBDA_SAV_PATH}'.\n"

    relabeled_sps_path = sps_path.sub(/\.sps\z/, '_relabeled.sps')
    File.write(relabeled_sps_path, rewritten)

    sav_path = sps_path.sub(/\.sps\z/, '.sav')
    ExportRelabeling::PsppLambdaClient.compile(sps_path: relabeled_sps_path, data_path: clean_data_path, output_path: sav_path)

    sav_path
  end

  def resolve_data_file_path(sps_text)
    match = FILE_HANDLE_NAME.match(sps_text)
    raise 'No se encontro FILE HANDLE NAME en la sintaxis' unless match

    original_name = File.basename(match[1].tr('\\', '/'))
    @work_dir.join(original_name).to_s
  end

  def strip_bom(data_path)
    content = File.read(data_path, mode: 'rb')
    return data_path unless content.start_with?(UTF8_BOM)

    clean_path = data_path.sub(/(\.[^.\/]+)\z/, '_nobom\1')
    File.write(clean_path, content.byteslice(UTF8_BOM.bytesize..-1), mode: 'wb')
    clean_path
  end
end
