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

  # 2 columnas vacias antes de "Answer Options" a pedido de Diego, para
  # separarla visualmente de las estadisticas numericas.
  DICTIONARY_HEADER = [
    'Variable', 'Code', 'Attribute', 'Question', 'Mean', 'Min', 'Max', 'Nulls', '% Nulls', 'Zeros',
    '', '', 'Answer Options'
  ].freeze

  # "status" es un campo de SISTEMA de Confirmit (no lo define cada
  # encuesta) -- su vocabulario ("complete", "screened", "quotafull", ...)
  # es fijo en ingles, confirmado identico en 2 proyectos reales
  # (p573989981944, p314244165357), asi que hardcodear el string es seguro.
  #
  # Un archivo de loop trae su propio campo de estado, pero ese SI es una
  # variable Hidden CUSTOM de cada proyecto (ej. "fichaestado") -- no hay
  # un nombre universal, asi que se busca cualquier variable que termine en
  # "estado" (dominio de Fine, encuestas en portugues) como mejor esfuerzo.
  # El criterio de "completa" es el LABEL, no el precode -- Diego: "el
  # criterio que importa es que el label sea completa (con fallback en
  # complete o en c), mas alla del valor del precode (que en general pero
  # no siempre es 2)". Se resuelve con
  # ConfirmitVariableLookup#answer_label_matching, que busca el texto real
  # entre TODAS las respuestas de esa variable en vez de asumir un precode.
  STATUS_VARIABLE = 'status'
  STATUS_COMPLETE_VALUE = 'complete'
  LOOP_STATUS_SUFFIX = /estado\z/i
  LOOP_COMPLETE_LABEL_CANDIDATES = %w[completa complete c].freeze

  # Tipo de nodo del schema que identifica una variable a nivel de fichas/
  # loop (ver ConfirmitVariableLookup#variable_type) -- se excluye del
  # proceso automatico de cuotas (ver #exclude_grid_quotas).
  GRID_VARIABLE_TYPE = 'Grid'

  WORK_ROOT = Rails.root.join('tmp', 'relabel_excel')

  def perform(zip_path, project_id, recipients, email_body = nil)
    @work_dir = WORK_ROOT.join(SecureRandom.uuid)
    FileUtils.mkdir_p(@work_dir)

    output_paths, relabeled = build_output_paths(zip_path, project_id, email_body)

    ExportDeliveryMailer.relabeled_export_email(recipients, project_id, output_paths, relabeled: relabeled).deliver_now
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
  # mejoras opcionales de #safely, que ya degradan solas sin llegar aca --
  # se manda el zip original TAL CUAL LLEGO en vez de no mandar nada.
  # Devuelve [paths_a_adjuntar, se_pudo_reetiquetar?].
  def build_output_paths(zip_path, project_id, email_body)
    extract_zip(zip_path, @work_dir)
    [relabel_all(project_id, email_body), true]
  rescue StandardError => e
    Rails.logger.error("[RelabelExcelExportWorker] fallo el pipeline de re-etiquetado, se manda la base sin cambios: #{e.class} #{e.message}")
    [[zip_path], false]
  end

  def relabel_all(project_id, email_body)
    lookup = ExportRelabeling::ConfirmitSchemaFetcher.call(project_id)

    sheets = xlsx_files.map { |path| [path, ExportRelabeling::ExcelReader.call(path)] }
    parsed_by_path = sheets.each_with_object({}) { |(path, sheet), acc| acc[path] = resolve_headers(sheet.headers, lookup) }
    sources = sheets.map { |_path, sheet| build_source(sheet, lookup) }
    manual = safely('parseo de cuotas/reportes manuales del mail', quotas: [], crosses: []) do
      ExportRelabeling::ManualQuotaRequestParser.call(email_body)
    end

    quota_rows = build_quota_rows(lookup, sources, manual[:quotas])
    report_rows = safely('hoja Report') { build_report_rows(manual[:crosses], sources) }
    dictionary_rows = safely('Dictionary consolidado') { build_consolidated_dictionary_rows(sheets, parsed_by_path, lookup) }

    sheets.map { |path, sheet| relabel(path, sheet, parsed_by_path[path], quota_rows, report_rows, dictionary_rows, lookup) }
  end

  # El proceso principal es que el cliente reciba la base re-etiquetada --
  # Diego: "si algun proceso falla se omite ese proceso y no se para el
  # reenvio de la base". Todo lo que es enriquecimiento OPCIONAL (cuotas,
  # report, diccionario/opciones de respuesta -- cualquier cosa que dependa
  # del schema en vivo de Confirmit o de texto libre de un PM) pasa por
  # esto: loguea y sigue con un default vacio en vez de tirar abajo todo el
  # worker (y con el, el envio del archivo base).
  def safely(feature, default = nil)
    yield
  rescue StandardError => e
    Rails.logger.error("[RelabelExcelExportWorker] #{feature} fallo, se omite: #{e.class} #{e.message}")
    default
  end

  def extract_zip(zip_path, work_dir)
    Zip::File.open(zip_path) do |zip_file|
      zip_file.each { |entry| entry.extract(work_dir.join(entry.name).to_s) }
    end
  end

  def xlsx_files
    Dir.glob(@work_dir.join('*.xlsx'))
  end

  # Las automaticas (desde las <Quota> de Confirmit, excluyendo las de tipo
  # Grid -- ver #exclude_grid_quotas) van primero; las declaradas a mano por
  # el PM (ver ManualQuotaRequestParser) se agregan abajo, separadas por una
  # fila en blanco -- nunca colapsan (collapse_loop_quotas: false), a
  # diferencia de las automaticas. Devuelve { rows:, header_indices: } (ver
  # QuotaProgressBuilder) o nil si no hay nada que mostrar.
  #
  # Las 2 mitades (automatica/manual) pasan por #safely POR SEPARADO -- si
  # el schema de Confirmit tiene alguna forma inesperada y rompe el calculo
  # de las automaticas, las manuales (que no dependen del schema para nada
  # mas que el label, ya resuelto con su propio fallback) igual se muestran,
  # y viceversa.
  def build_quota_rows(lookup, sources, manual_quota_lines)
    auto_result = safely('cuotas automaticas') { build_auto_quota_result(lookup, sources) }
    manual_result = safely('cuotas manuales del mail') { build_manual_quota_result(lookup, sources, manual_quota_lines) }

    merge_quota_results(auto_result, manual_result)
  end

  def build_auto_quota_result(lookup, sources)
    return nil unless lookup

    auto_quotas = exclude_grid_quotas(lookup.quotas, lookup)
    return nil if auto_quotas.blank?

    ExportRelabeling::QuotaProgressBuilder.call(quotas: auto_quotas, sources: sources)
  end

  def build_manual_quota_result(lookup, sources, manual_quota_lines)
    manual_quotas = manual_quota_lines.map { |line| build_manual_quota(line, lookup) }
    return nil if manual_quotas.blank?

    ExportRelabeling::QuotaProgressBuilder.call(quotas: manual_quotas, sources: sources, collapse_loop_quotas: false)
  end

  def merge_quota_results(auto_result, manual_result)
    return manual_result if auto_result.blank? || auto_result[:rows].blank?
    return auto_result if manual_result.blank? || manual_result[:rows].blank?

    offset = auto_result[:rows].length + 1
    {
      rows: auto_result[:rows] + [blank_quota_row] + manual_result[:rows],
      header_indices: auto_result[:header_indices] + manual_result[:header_indices].map { |i| i + offset }
    }
  end

  def blank_quota_row
    Array.new(ExportRelabeling::QuotaProgressBuilder::HEADER.length)
  end

  # Una cuota que involucre AUNQUE SEA UNA variable de tipo Grid (fichas,
  # ej. "qregion") se excluye completa -- Diego: "las grids... ni las
  # miraria ya que los datos internos ni nos sirven". Una cuota sin ningun
  # QuotaField (la meta total del proyecto) nunca tiene variables Grid, asi
  # que nunca se excluye por este criterio.
  def exclude_grid_quotas(quotas, lookup)
    quotas.reject { |quota| quota_has_grid_field?(quota, lookup) }
  end

  def quota_has_grid_field?(quota, lookup)
    quota[:cells].flat_map { |cell| cell[:fields] }.any? { |field| lookup.variable_type(field[:name]) == GRID_VARIABLE_TYPE }
  end

  def build_manual_quota(line, lookup)
    {
      name: line[:variable],
      cells: line[:targets].map do |target|
        {
          limit: target[:meta],
          fields: [{
            name: line[:variable],
            precode: nil,
            value: target[:precode],
            label: lookup&.answer_label(line[:variable], target[:precode])
          }]
        }
      end
    }
  end

  # Devuelve { rows:, header_indices: } (ver CrosstabBuilder) o nil.
  def build_report_rows(crosses, sources)
    return nil if crosses.blank?

    ExportRelabeling::CrosstabBuilder.call(crosses: crosses, sources: sources)
  end

  def build_source(sheet, lookup)
    config = status_config(sheet, lookup)
    { headers: sheet.headers, rows: sheet.rows, status_variable: config[:status_variable], complete_value: config[:complete_value] }
  end

  # Bug real (encontrado por Diego): si ConfirmitSchemaFetcher no pudo
  # traer el schema (timeout, proyecto sin acceso -- ese servicio ya
  # rescata el error y devuelve nil a proposito, ver su comentario), esto
  # llamaba a `lookup.answer_label_matching` sobre un `nil` -- un
  # NoMethodError que tiraba abajo TODO el worker antes de mandar nada, ni
  # siquiera el archivo base sin cuotas. `lookup&.` + #safely: sin schema,
  # este archivo de loop simplemente queda sin filtro de completitud
  # (status_variable/complete_value en nil) en vez de romper el envio.
  def status_config(sheet, lookup)
    return { status_variable: STATUS_VARIABLE, complete_value: STATUS_COMPLETE_VALUE } if variable?(sheet, STATUS_VARIABLE)

    loop_status = sheet.headers.find { |h| h.variable_name.to_s.match?(LOOP_STATUS_SUFFIX) }
    return { status_variable: nil, complete_value: nil } unless loop_status

    complete_value = safely('deteccion de completitud del loop') do
      lookup&.answer_label_matching(loop_status.variable_name, LOOP_COMPLETE_LABEL_CANDIDATES)
    end
    { status_variable: loop_status.variable_name, complete_value: complete_value }
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
      extra_sheets: extra_sheets_for(sheet, parsed, quota_rows, report_rows, dictionary_rows, lookup),
      date_columns: sheet.date_columns,
      output_path: output_path
    )

    output_path
  end

  def extra_sheets_for(sheet, parsed, quota_rows, report_rows, dictionary_rows, lookup)
    is_main = variable?(sheet, STATUS_VARIABLE)
    own_dictionary = safely('Dictionary propio del loop') { build_dictionary_rows(sheet.headers, parsed, sheet.rows, lookup) }

    sheets = { 'Dictionary' => is_main ? dictionary_rows : own_dictionary }
    sheets['Quotas'] = highlighted_sheet(quota_rows) if quota_rows.present? && is_main
    sheets['Report'] = highlighted_sheet(report_rows) if report_rows.present? && is_main
    sheets
  end

  # quota_rows/report_rows llegan como { rows:, header_indices: } (ver
  # QuotaProgressBuilder/CrosstabBuilder) -- se traducen al formato que
  # espera ExcelWriter para resaltar en negrita + fondo amarillo los
  # encabezados repetidos de cada bloque/titulo.
  def highlighted_sheet(result)
    { rows: result[:rows], highlighted_rows: result[:header_indices] }
  end

  # El principal es el unico con "status" -- si por algun motivo ninguno lo
  # tiene (no deberia pasar, pero mejor no reventar), se usa el primer
  # archivo como principal y no se agrega ninguna seccion de loop.
  def build_consolidated_dictionary_rows(sheets, parsed_by_path, lookup)
    main_path, main_sheet = sheets.find { |_path, sheet| variable?(sheet, STATUS_VARIABLE) } || sheets.first
    rows = build_dictionary_rows(main_sheet.headers, parsed_by_path[main_path], main_sheet.rows, lookup)

    sheets.each do |loop_path, loop_sheet|
      next if loop_path == main_path

      rows += [blank_dictionary_row, loop_section_title(main_path, loop_path)]
      rows += build_dictionary_rows(loop_sheet.headers, parsed_by_path[loop_path], loop_sheet.rows, lookup)
    end

    rows
  end

  # El nombre del loop se deriva del propio nombre de archivo que ya usa
  # Confirmit para separarlos (ej. "..._fichas.xlsx" vs "...xlsx" del
  # principal) -- no hace falta declararlo a mano, es la misma convencion
  # que ya usamos en toda la clase para encontrar los .xlsx del zip.
  def loop_section_title(main_path, loop_path)
    main_base = File.basename(main_path.to_s, '.xlsx')
    loop_base = File.basename(loop_path.to_s, '.xlsx')
    label = loop_base.sub(main_base, '').sub(/\A_/, '').presence || loop_base

    [label.titleize] + Array.new(DICTIONARY_HEADER.length - 1)
  end

  def blank_dictionary_row
    Array.new(DICTIONARY_HEADER.length)
  end

  # Si el schema de Confirmit tiene alguna forma inesperada para ESA
  # variable puntual (Nokogiri sobre datos reales, no hay garantia de
  # cubrir cada caso), el fallback es LabelParser directo sobre el label
  # ya compuesto que trae el propio Excel (evitando volver a pasar por el
  # lookup que rompio) -- una columna con un label mas simple es preferible
  # a perder el archivo entero.
  def resolve_headers(headers, lookup)
    headers.map { |header| resolve_header(header, lookup) }
  end

  def resolve_header(header, lookup)
    ExportRelabeling::VariableLabelResolver.call(variable_name: header.variable_name, raw_label: header.raw_label, lookup: lookup)
  rescue StandardError => e
    Rails.logger.error("[RelabelExcelExportWorker] resolucion de header #{header.variable_name} fallo, uso fallback: #{e.class} #{e.message}")
    ExportRelabeling::LabelParser.call(header.raw_label)
  end

  # 3 filas de encabezado (codigo / atributo / pregunta) en vez del string
  # unico "codigo | atributo | pregunta" que usa SPSS -- decision ya
  # tomada, mas practico para trabajar en Excel que un solo string largo
  # por columna. Una variable sin codigo/atributo detectable (sistema, o
  # sin el patron "codigo - pregunta") deja esas 2 filas vacias y el
  # texto tal cual en la fila de pregunta.
  def build_header_rows(parsed)
    [
      parsed.map { |p| p[:code] },
      parsed.map { |p| p[:attribute] },
      parsed.map { |p| p[:question] }
    ]
  end

  # Misma resolucion que las 3 filas de encabezado, pero en formato tabla
  # (una fila por variable) para que sea legible como diccionario, en vez
  # de tener que leer las 3 filas columna por columna en la hoja principal.
  # Suma las estadisticas por columna que pidio el cliente (ver
  # ExportRelabeling::ColumnStatistics) -- se calculan sobre los valores ya
  # presentes en este mismo Excel, no dependen del .sps ni de la API.
  def build_dictionary_rows(headers, parsed, rows, lookup)
    entries = headers.each_with_index.map do |header, index|
      stats = ExportRelabeling::ColumnStatistics.call(rows.map { |row| row[index] })

      [
        header.variable_name,
        parsed[index][:code],
        parsed[index][:attribute],
        parsed[index][:question],
        stats[:mean],
        stats[:min],
        stats[:max],
        stats[:null_count],
        stats[:null_percentage],
        stats[:zero_count],
        nil,
        nil,
        format_answer_options(lookup, header.variable_name)
      ]
    end

    [DICTIONARY_HEADER] + entries
  end

  # Solo tiene contenido para preguntas Single (ver
  # ConfirmitVariableLookup#answer_options) -- una Multi ya muestra el
  # texto de su propia opcion en la columna "Atributo" de esa misma fila,
  # no hace falta repetirlo aca.
  def format_answer_options(lookup, variable_name)
    return nil unless lookup

    options = safely("opciones de respuesta de #{variable_name}", []) { lookup.answer_options(variable_name) }
    return nil if options.blank?

    options.map { |precode, text| "#{precode}=#{text}" }.join('; ')
  end
end
