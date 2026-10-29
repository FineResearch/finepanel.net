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
#
# Ademas de los .sav, arma una planilla "<project_id>_metadata.xlsx" con
# Dictionary/Quotas/Report (sin los datos -- Diego: "se puede obtener estos
# datos para crear el excel si el envio incluye los .dat y sps?") -- la
# misma info que ya arma RelabelExcelExportWorker, reusando
# ExportRelabeling::ExportMetadataBuilder (compartido entre los 2
# workers) sobre un Sheet armado por ExportRelabeling::SpssDataListReader
# en vez de ExportRelabeling::ExcelReader (el .sps trae las posiciones de
# columna del .dat via DATA LIST, suficiente para leer filas/columnas sin
# pasar por PSPP). Esto es una mejora OPCIONAL, separada del compile a
# .sav -- si falla, se sigue mandando los .sav igual, solo sin la planilla
# (ver #build_metadata_excel).
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

  def perform(zip_path, project_id, recipients, email_body = nil, project_title = nil, interview_status_filter = nil)
    @work_dir = WORK_ROOT.join(SecureRandom.uuid)
    FileUtils.mkdir_p(@work_dir)
    @permission_denied = false

    output_paths, relabeled, metadata_info, delivery_zip_name = build_output_paths(zip_path, project_id, email_body)

    ExportDeliveryMailer.relabeled_export_email(
      recipients, project_id, output_paths, export_type: :spss, relabeled: relabeled,
      project_title: project_title, interview_status_filter: interview_status_filter,
      includes_quotas: metadata_info[:includes_quotas], includes_report: metadata_info[:includes_report],
      includes_dictionary: metadata_info[:includes_dictionary], completed_quotas: metadata_info[:completed_quotas],
      delivery_zip_name: delivery_zip_name
    ).deliver_now

    ExportRelabeling::ProcessingAlertNotifier.call(
      recipients: recipients, project_id: project_id, export_type: :spss,
      permission_denied: @permission_denied, relabeled: relabeled
    )
  ensure
    FileUtils.rm_rf(@work_dir) if @work_dir
    File.delete(zip_path) if zip_path && File.exist?(zip_path)
  end

  private

  # El proceso principal es que el cliente reciba la base -- Diego: "lo mas
  # seguro seria que si algo falla se envie lo mismo que se recibio... asi
  # cubrimos el riesgo de que los datos se enviaron aunque el formato no
  # fuera perfecto". A diferencia de Excel (que separa base + mejoras
  # opcionales), el compile a .sav ES el producto -- no hay una version
  # "mas simple" intermedia a la que degradar, asi que un fallo ahi cae
  # directo al zip original tal cual llego. La planilla de metadata
  # (Dictionary/Quotas/Report) SI es una mejora opcional aparte -- si
  # falla, los .sav igual se mandan (ver #build_metadata_excel).
  # Devuelve [paths_a_adjuntar, se_pudo_reetiquetar?, metadata_info].
  def build_output_paths(zip_path, project_id, email_body)
    lookup = build_lookup(project_id)
    extract_zip(zip_path, @work_dir)
    # Capturado ANTES de compilar a proposito: #build_sav escribe un
    # "..._relabeled.sps" por cada archivo, en el MISMO @work_dir -- si
    # #build_metadata_excel volviera a globear *.sps despues, agarraria
    # tambien esos (y los procesaria como si fueran loops aparte, con los
    # labels ya reescritos en formato "codigo | atributo | pregunta").
    original_sps_files = sps_files
    delivery_zip_name = main_file_basename(original_sps_files)
    sav_paths = original_sps_files.map { |sps_path| build_sav(sps_path, lookup) }

    metadata_path, metadata_info = build_metadata_excel(original_sps_files, email_body, lookup)
    output_paths = metadata_path ? sav_paths + [metadata_path] : sav_paths

    [output_paths, true, metadata_info, delivery_zip_name]
  rescue StandardError => e
    Rails.logger.error("[RelabelSpssExportWorker] fallo el pipeline de re-etiquetado, se manda la base sin cambios: #{e.class} #{e.message}")
    [[zip_path], false, blank_metadata_info, nil]
  end

  # Diego: el zip de entrega final (ver ExportDeliveryMailer) tiene que
  # llamarse igual que el archivo PRINCIPAL, nunca el de loop (ej.
  # fichas) -- mismo criterio ya usado para detectar el principal en
  # #loop_section_title (el nombre del archivo de loop siempre EXTIENDE
  # al del principal, nunca al reves, asi que el basename mas corto es
  # el principal). Se calcula solo con el filename (sin depender de que
  # el schema/parseo de metadata funcione) para que el nombre del zip
  # nunca dependa de una mejora opcional que puede fallar sola.
  def main_file_basename(sps_files)
    return nil if sps_files.blank?

    main = sps_files.min_by { |path| File.basename(path).length }
    "#{File.basename(main, File.extname(main))}_relabeled"
  end

  # Mejora OPCIONAL (igual criterio que RelabelExcelExportWorker): si algo
  # aca rompe (un .sps con un DATA LIST que no matchea el patron esperado,
  # etc.) se omite la planilla entera en vez de tirar abajo el envio de
  # los .sav ya compilados.
  def build_metadata_excel(sps_files, email_body, lookup)
    sheets = sps_files.map { |sps_path| metadata_sheet_for(sps_path) }.compact
    return [nil, blank_metadata_info] if sheets.empty?

    metadata = ExportRelabeling::ExportMetadataBuilder.call(sheets: sheets, lookup: lookup, email_body: email_body)
    return [nil, blank_metadata_info] if metadata[:dictionary_rows].blank? && metadata[:quota_rows].blank? && metadata[:report_rows].blank?

    [write_metadata_excel(main_sps_path(sheets), metadata), metadata_info_from(metadata)]
  rescue StandardError => e
    Rails.logger.error("[RelabelSpssExportWorker] no se pudo armar la planilla de Dictionary/Quotas/Report, se omite: #{e.class} #{e.message}")
    [nil, blank_metadata_info]
  end

  # Diego: "a veces el archivo puede venir con otro nombre que no sea el
  # estandard con pxxxx... en todos los casos es importante... que el
  # nombre del archivo se mantenga" -- el nombre de esta planilla nunca
  # debe depender de project_id (que puede venir de un fallback, el
  # "Survey ID" del cuerpo del mail, cuando el nombre del archivo no trae
  # el patron estandard) sino del nombre ORIGINAL del archivo PRINCIPAL
  # de SPSS tal cual llego (Diego: "usemos el mismo nombre del archivo
  # principal en spss"). "Principal" = el que tiene la variable de
  # sistema "status" (mismo criterio que ExportMetadataBuilder usa para
  # elegir main_path); sin loop de por medio, sheets solo tiene un
  # elemento.
  def main_sps_path(sheets)
    main = sheets.find do |_path, sheet|
      sheet.headers.any? { |h| h.variable_name.to_s.casecmp?(ExportRelabeling::ExportMetadataBuilder::STATUS_VARIABLE) }
    end
    (main || sheets.first).first
  end

  def metadata_sheet_for(sps_path)
    original = File.read(sps_path, encoding: 'bom|utf-8')
    data_path = resolve_data_file_path(original)
    return nil unless File.exist?(data_path)

    [sps_path, ExportRelabeling::SpssDataListReader.call(sps_text: original, data_path: data_path)]
  rescue StandardError => e
    Rails.logger.error("[RelabelSpssExportWorker] no se pudo leer #{sps_path} para la planilla de metadata, se omite ese archivo: #{e.class} #{e.message}")
    nil
  end

  def write_metadata_excel(main_sps_path, metadata)
    # Diego: "anteponiendo 'Progress_report_'" -- prefijo, no sufijo, y
    # sobre el nombre del .sps principal tal cual llego (ver
    # #main_sps_path), nunca sobre project_id.
    base_name = File.basename(main_sps_path, File.extname(main_sps_path))
    output_path = @work_dir.join("Progress_report_#{base_name}.xlsx").to_s
    extra_sheets = {}
    extra_sheets['Quotas'] = highlighted_sheet(metadata[:quota_rows]) if metadata[:quota_rows].present?
    extra_sheets['Report'] = highlighted_sheet(metadata[:report_rows]) if metadata[:report_rows].present?

    ExportRelabeling::ExcelWriter.call(
      sheet_name: 'Dictionary',
      header_rows: [],
      data_rows: metadata[:dictionary_rows] || [],
      extra_sheets: extra_sheets,
      output_path: output_path
    )

    output_path
  end

  # quota_rows/report_rows llegan como { rows:, header_indices: } (ver
  # QuotaProgressBuilder/CrosstabBuilder) -- mismo formato que espera
  # ExcelWriter para resaltar en negrita + fondo amarillo los encabezados
  # repetidos de cada bloque/titulo (ver RelabelExcelExportWorker, mismo
  # helper).
  def highlighted_sheet(result)
    { rows: result[:rows], highlighted_rows: result[:header_indices] }
  end

  def metadata_info_from(metadata)
    {
      includes_quotas: metadata[:includes_quotas],
      includes_report: metadata[:includes_report],
      includes_dictionary: metadata[:includes_dictionary],
      completed_quotas: metadata[:completed_quotas]
    }
  end

  def blank_metadata_info
    { includes_quotas: false, includes_report: false, includes_dictionary: false, completed_quotas: [] }
  end

  def build_lookup(project_id)
    ExportRelabeling::ConfirmitSchemaFetcher.call(project_id)
  rescue ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError
    @permission_denied = true
    nil
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

    # Diego: mismo criterio que ya usa Excel (ver #relabel en
    # RelabelExcelExportWorker) -- el nombre de salida se basa SIEMPRE en
    # el nombre ORIGINAL del archivo que llego, nunca en project_id,
    # agregando "_relabeled" para distinguirlo del original.
    sav_path = sps_path.sub(/\.sps\z/, '_relabeled.sav')
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
