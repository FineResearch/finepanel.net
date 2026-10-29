# frozen_string_literal: true

require 'zip'

# Recibe el zip que Confirmit manda con el/los .xlsx de un export, corrige
# los encabezados (formato "codigo | atributo | pregunta" en 3 filas, ver
# ExportRelabeling::LabelParser) y manda el resultado por mail.
#
# Como el .xlsx y el .sps son 2 procesos separados (cada uno con su propia
# Rule/mail en Confirmit), este worker nunca depende del otro -- ver
# RelabelSpssExportWorker para la mitad de SPSS.
#
# Igual que con SPSS, un zip puede traer mas de un .xlsx (los loops de la
# encuesta como archivo separado, ej. "..._fichas.xlsx") -- se procesan
# todos, un archivo de salida por cada uno.
#
# El texto de la API es la fuente principal para el codigo/atributo/
# pregunta (ver ExportRelabeling::VariableLabelResolver) -- el label ya
# compuesto que trae el propio Excel (LabelParser) queda solo de fallback,
# para variables que la API no resuelve (de sistema, o en un loop que el
# schema principal no trae).
#
# Ademas de los encabezados de la hoja principal, agrega una segunda hoja
# "Dictionary" -- una fila por variable EXPORTADA (no todo el cuestionario
# completo de Confirmit), porque el Data Template ya restringe las columnas
# a lo que el cliente necesita ver -- decision ya tomada, evita duplicar esa
# restriccion aca (ver ExcelWriter#write_dictionary_sheet). En el archivo
# PRINCIPAL, ese Dictionary viene consolidado (variables generales primero,
# despues cada loop -- ej. fichas -- debajo, separado con su propio titulo)
# -- Diego: "sería bueno tener detalle de los loops también... lo colocaría
# debajo del archivo general separado más abajo con el título de cada
# loop", para no tener que abrir el archivo de salida del loop aparte solo
# para ver sus variables. El archivo de cada loop igual conserva su propio
# Dictionary acotado (solo sus variables), por si se abre ese archivo solo.
#
# Tambien agrega una hoja "Quotas" (progreso de campo, ver
# ExportRelabeling::QuotaProgressBuilder) -- SOLO al archivo que tiene la
# variable de sistema "status" (el archivo principal, por entrevistado), no
# a cada archivo del zip -- si hay un loop (ej. fichas), sus filas se usan
# igual para contar las cuotas que viven ahi, pero la hoja de resumen no se
# duplica en su propio archivo de salida. Las cuotas de tipo Grid (fichas,
# ej. "qregion") se excluyen del proceso automatico -- ver
# #exclude_grid_quotas -- porque el conteo interno de Confirmit para ese
# tipo de variable no es confiable desde el export (ver comentario de
# ConfirmitVariableLookup#quotas).
#
# Un PM puede pedir cuotas/cruces adicionales escribiendolos en el cuerpo
# del mail (ver ExportRelabeling::ManualQuotaRequestParser) -- util sobre
# todo para lo que las <Quota> de Confirmit no pueden cubrir (variables
# tipo Grid). Las cuotas declaradas a mano se agregan ABAJO de las
# automaticas en la misma hoja "Quotas", separadas por una fila en blanco,
# nunca colapsan (a diferencia de las automaticas, el PM eligio esa meta a
# proposito). Los cruces sin meta ("Report:") van en una hoja nueva
# "Report", como crosstab de conteos.
class RelabelExcelExportWorker
  include Sidekiq::Worker
  sidekiq_options retry: 3

  # El Dictionary/Quotas/Report/completed_quotas (constantes incluidas, ver
  # STATUS_VARIABLE/LOOP_STATUS_SUFFIX/etc ahi) vive en
  # ExportRelabeling::ExportMetadataBuilder -- compartido con
  # RelabelSpssExportWorker, que arma la misma info pero leyendo un .sps+.dat
  # en vez de un .xlsx (ver ExportRelabeling::SpssDataListReader).
  DICTIONARY_HEADER = ExportRelabeling::ExportMetadataBuilder::DICTIONARY_HEADER
  STATUS_VARIABLE = ExportRelabeling::ExportMetadataBuilder::STATUS_VARIABLE

  WORK_ROOT = Rails.root.join('tmp', 'relabel_excel')

  def perform(zip_path, project_id, recipients, email_body = nil, project_title = nil, interview_status_filter = nil)
    @work_dir = WORK_ROOT.join(SecureRandom.uuid)
    FileUtils.mkdir_p(@work_dir)
    @permission_denied = false

    output_paths, relabeled, includes_quotas, includes_report, includes_dictionary, completed_quotas, delivery_zip_name =
      build_output_paths(zip_path, project_id, email_body)

    ExportDeliveryMailer.relabeled_export_email(
      recipients, project_id, output_paths, export_type: :excel, relabeled: relabeled,
      includes_quotas: includes_quotas, includes_report: includes_report, includes_dictionary: includes_dictionary,
      project_title: project_title, interview_status_filter: interview_status_filter,
      completed_quotas: completed_quotas, delivery_zip_name: delivery_zip_name
    ).deliver_now

    ExportRelabeling::ProcessingAlertNotifier.call(
      recipients: recipients, project_id: project_id, export_type: :excel,
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
  # fuera perfecto". Si el pipeline central (descomprimir/leer/re-
  # etiquetar/escribir) revienta en CUALQUIER punto -- a diferencia de las
  # mejoras opcionales de ExportMetadataBuilder, que ya degradan solas sin
  # llegar aca -- se manda el zip original TAL CUAL LLEGO en vez de no
  # mandar nada.
  # Devuelve [paths_a_adjuntar, se_pudo_reetiquetar?, incluye_cuotas?, incluye_report?, incluye_dictionary?, cuotas_completas, delivery_zip_name].
  def build_output_paths(zip_path, project_id, email_body)
    extract_zip(zip_path, @work_dir)
    output_paths, includes_quotas, includes_report, includes_dictionary, completed_quotas, delivery_zip_name =
      relabel_all(project_id, email_body)
    [output_paths, true, includes_quotas, includes_report, includes_dictionary, completed_quotas, delivery_zip_name]
  rescue StandardError => e
    Rails.logger.error("[RelabelExcelExportWorker] fallo el pipeline de re-etiquetado, se manda la base sin cambios: #{e.class} #{e.message}")
    [[zip_path], false, false, false, false, [], nil]
  end

  def relabel_all(project_id, email_body)
    lookup = build_lookup(project_id)
    sheets = xlsx_files.map { |path| [path, ExportRelabeling::ExcelReader.call(path)] }

    metadata = ExportRelabeling::ExportMetadataBuilder.call(sheets: sheets, lookup: lookup, email_body: email_body)

    output_paths = sheets.map do |path, sheet|
      relabel(path, sheet, metadata[:parsed_by_path][path], metadata[:quota_rows], metadata[:report_rows], metadata[:dictionary_rows], lookup)
    end
    delivery_zip_name = main_file_basename(sheets)
    [output_paths, metadata[:includes_quotas], metadata[:includes_report], metadata[:includes_dictionary], metadata[:completed_quotas], delivery_zip_name]
  end

  # Diego: mismo criterio que RelabelSpssExportWorker -- el zip de
  # entrega final (ver ExportDeliveryMailer) tiene que llamarse igual
  # que el archivo PRINCIPAL (el que tiene la variable de sistema
  # "status"), nunca uno de loop (ej. fichas).
  def main_file_basename(sheets)
    return nil if sheets.blank?

    main_path, = sheets.find { |path, sheet| variable?(sheet, STATUS_VARIABLE) } || sheets.first
    "#{File.basename(main_path, File.extname(main_path))}_relabeled"
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

  def xlsx_files
    Dir.glob(@work_dir.join('*.xlsx'))
  end

  def variable?(sheet, name)
    sheet.headers.any? { |h| h.variable_name.to_s.casecmp?(name) }
  end

  def relabel(xlsx_path, sheet, parsed, quota_rows, report_rows, dictionary_rows, lookup)
    output_path = xlsx_path.sub(/\.xlsx\z/, '_relabeled.xlsx')
    ExportRelabeling::ExcelWriter.call(
      sheet_name: sheet.name,
      header_rows: build_header_rows(parsed),
      data_rows: sheet.rows,
      extra_sheets: extra_sheets_for(sheet, quota_rows, report_rows, dictionary_rows, lookup),
      date_columns: sheet.date_columns,
      output_path: output_path
    )

    output_path
  end

  def extra_sheets_for(sheet, quota_rows, report_rows, dictionary_rows, lookup)
    is_main = variable?(sheet, STATUS_VARIABLE)
    own_dictionary = safely('Dictionary propio del loop') { build_own_dictionary_rows(sheet, lookup) }

    sheets = { 'Dictionary' => is_main ? dictionary_rows : own_dictionary }
    sheets['Quotas'] = highlighted_sheet(quota_rows) if quota_rows.present? && is_main
    sheets['Report'] = highlighted_sheet(report_rows) if report_rows.present? && is_main
    sheets
  end

  # Mismo calculo que ExportMetadataBuilder usa para el Dictionary
  # consolidado, pero acotado a este unico archivo (el Dictionary propio
  # de un loop, para cuando se abre ese archivo de salida solo) -- se arma
  # con un ExportMetadataBuilder de un solo sheet en vez de duplicar la
  # logica de ColumnStatistics/answer_options aca.
  def build_own_dictionary_rows(sheet, lookup)
    ExportRelabeling::ExportMetadataBuilder.call(sheets: [['own', sheet]], lookup: lookup)[:dictionary_rows]
  end

  def safely(feature, default = nil)
    yield
  rescue StandardError => e
    Rails.logger.error("[RelabelExcelExportWorker] #{feature} fallo, se omite: #{e.class} #{e.message}")
    default
  end

  # quota_rows/report_rows llegan como { rows:, header_indices: } (ver
  # QuotaProgressBuilder/CrosstabBuilder) -- se traducen al formato que
  # espera ExcelWriter para resaltar en negrita + fondo amarillo los
  # encabezados repetidos de cada bloque/titulo.
  def highlighted_sheet(result)
    { rows: result[:rows], highlighted_rows: result[:header_indices] }
  end

  # 3 filas de encabezado (codigo / atributo / pregunta) en vez del string
  # unico "codigo | atributo | pregunta" que usa SPSS -- decision ya
  # tomada, mas practico para trabajar en Excel que un solo string largo
  # por columna. Una variable sin codigo/atributo detectable (sistema, o
  # sin el patron "codigo - pregunta") deja esas 2 filas vacias y el
  # texto tal cual en la fila de pregunta.
  #
  # Diego: en un archivo de loop (ej. fichas), el codigo de CADA variable
  # trae pegado un piping sin resolver que Confirmit agrega como
  # referencia al loop (ej. "Q0A // ^f('hidden_ficha_nom')^", identico en
  # TODA fila) -- en el Dictionary eso queda tal cual a proposito (ver
  # ExportMetadataBuilder/LabelParser, "no molesta"), pero en el
  # encabezado de la tabla de DATOS se ve mejor separado en su propia
  # fila en vez de pisar la fila de Codigo. Se agrega esa 4ta fila SOLO
  # cuando aparece (nunca para el archivo principal, que no tiene este
  # patron en ninguna columna) -- ver LabelParser.split_loop_reference.
  def build_header_rows(parsed)
    codes_and_refs = parsed.map { |p| ExportRelabeling::LabelParser.split_loop_reference(p[:code]) }
    codes = codes_and_refs.map(&:first)
    loop_refs = codes_and_refs.map(&:last)

    rows = [codes]
    rows << loop_refs if loop_refs.any?(&:present?)
    rows << parsed.map { |p| p[:attribute] }
    rows << parsed.map { |p| p[:question] }
    rows
  end
end
