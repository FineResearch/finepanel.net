# frozen_string_literal: true

# Arma el Dictionary/Quotas/Report/completed_quotas compartidos entre los 2
# pipelines de export (RelabelExcelExportWorker y RelabelSpssExportWorker)
# -- extraido de RelabelExcelExportWorker a proposito: la logica de cuotas/
# report/diccionario no depende de que la fuente sea un .xlsx o un .sps+.dat,
# solo necesita la misma forma generica { headers:, rows: } por archivo (ver
# ExportRelabeling::ExcelReader::Sheet, que ExportRelabeling::SpssDataListReader
# tambien produce para que esto sea intercambiable).
#
# "sheets" es un array de [identificador, Sheet] -- el identificador se usa
# solo para distinguir el archivo principal del/los loop(s) en el titulo del
# Dictionary consolidado (ver #loop_section_title), nunca se interpreta como
# un path real.
module ExportRelabeling
  class ExportMetadataBuilder
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

    def self.call(sheets:, lookup:, email_body: nil)
      new(sheets, lookup, email_body).call
    end

    def initialize(sheets, lookup, email_body)
      @sheets = sheets
      @lookup = lookup
      @email_body = email_body
    end

    def call
      parsed_by_path = @sheets.each_with_object({}) { |(path, sheet), acc| acc[path] = resolve_headers(sheet.headers) }
      sources = @sheets.map { |_path, sheet| build_source(sheet) }
      manual = safely('parseo de cuotas/reportes manuales del mail', quotas: [], crosses: []) do
        ExportRelabeling::ManualQuotaRequestParser.call(@email_body)
      end

      quota_rows = build_quota_rows(sources, manual[:quotas])
      report_rows = safely('hoja Report') { build_report_rows(manual[:crosses], sources) }
      dictionary_rows = safely('Dictionary consolidado') { build_consolidated_dictionary_rows(parsed_by_path) }
      completed_quotas = safely('cuotas completas para el cuerpo del mail', []) { ExportRelabeling::CompletedQuotas.call(quota_rows && quota_rows[:rows]) }

      {
        parsed_by_path: parsed_by_path,
        quota_rows: quota_rows,
        report_rows: report_rows,
        dictionary_rows: dictionary_rows,
        completed_quotas: completed_quotas,
        includes_quotas: quota_rows.present?,
        includes_report: report_rows.present?,
        includes_dictionary: dictionary_rows.present?
      }
    end

    private

    # El proceso principal es que el cliente reciba la base re-etiquetada --
    # Diego: "si algun proceso falla se omite ese proceso y no se para el
    # reenvio de la base". Todo lo que es enriquecimiento OPCIONAL (cuotas,
    # report, diccionario/opciones de respuesta -- cualquier cosa que dependa
    # del schema en vivo de Confirmit o de texto libre de un PM) pasa por
    # esto: loguea y sigue con un default vacio en vez de tirar abajo todo el
    # proceso (y con el, el envio del archivo base).
    def safely(feature, default = nil)
      yield
    rescue StandardError => e
      Rails.logger.error("[ExportMetadataBuilder] #{feature} fallo, se omite: #{e.class} #{e.message}")
      default
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
    def build_quota_rows(sources, manual_quota_lines)
      auto_result = safely('cuotas automaticas') { build_auto_quota_result(sources) }
      manual_result = safely('cuotas manuales del mail') { build_manual_quota_result(sources, manual_quota_lines) }

      merge_quota_results(auto_result, manual_result)
    end

    def build_auto_quota_result(sources)
      return nil unless @lookup

      auto_quotas = exclude_grid_quotas(@lookup.quotas)
      return nil if auto_quotas.blank?

      ExportRelabeling::QuotaProgressBuilder.call(quotas: auto_quotas, sources: sources)
    end

    def build_manual_quota_result(sources, manual_quota_lines)
      manual_quotas = manual_quota_lines.map { |line| build_manual_quota(line) }
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
    def exclude_grid_quotas(quotas)
      quotas.reject { |quota| quota_has_grid_field?(quota) }
    end

    def quota_has_grid_field?(quota)
      quota[:cells].flat_map { |cell| cell[:fields] }.any? { |field| @lookup.variable_type(field[:name]) == GRID_VARIABLE_TYPE }
    end

    def build_manual_quota(line)
      {
        name: line[:variable],
        cells: line[:targets].map do |target|
          {
            limit: target[:meta],
            fields: [{
              name: line[:variable],
              precode: nil,
              value: target[:precode],
              label: @lookup&.answer_label(line[:variable], target[:precode])
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

    def build_source(sheet)
      config = status_config(sheet)
      {
        headers: sheet.headers, rows: sheet.rows, status_variable: config[:status_variable],
        complete_value: config[:complete_value], complete_precode: config[:complete_precode]
      }
    end

    # Bug real (encontrado por Diego): si ConfirmitSchemaFetcher no pudo
    # traer el schema (timeout, proyecto sin acceso -- ese servicio ya
    # rescata el error y devuelve nil a proposito, ver su comentario), esto
    # llamaba a `lookup.answer_label_matching` sobre un `nil` -- un
    # NoMethodError que tiraba abajo TODO el worker antes de mandar nada, ni
    # siquiera el archivo base sin cuotas. `lookup&.` + #safely: sin schema,
    # este archivo de loop simplemente queda sin filtro de completitud
    # (status_variable/complete_value en nil) en vez de romper el envio.
    def status_config(sheet)
      return { status_variable: STATUS_VARIABLE, complete_value: STATUS_COMPLETE_VALUE } if variable?(sheet, STATUS_VARIABLE)

      loop_status = sheet.headers.find { |h| h.variable_name.to_s.match?(LOOP_STATUS_SUFFIX) }
      return { status_variable: nil, complete_value: nil, complete_precode: nil } unless loop_status

      # [precode, texto] en vez de solo el texto -- ver
      # ConfirmitVariableLookup#answer_option_matching y
      # QuotaProgressBuilder#complete?: confirmado contra un export real de
      # SPSS (p573989981944) que la columna de estado del loop
      # ("fichaestado") trae el PRECODE numerico crudo en el .dat, nunca el
      # texto "completa" que resuelve el schema -- sin el precode como
      # candidato alternativo, #complete? no matchea NUNCA para SPSS
      # (silencioso, sin excepcion) y toda cuota de loop sale "Achieved: 0".
      complete_option = safely('deteccion de completitud del loop') do
        @lookup&.answer_option_matching(loop_status.variable_name, LOOP_COMPLETE_LABEL_CANDIDATES)
      end
      complete_precode, complete_value = complete_option
      { status_variable: loop_status.variable_name, complete_value: complete_value, complete_precode: complete_precode }
    end

    def variable?(sheet, name)
      sheet.headers.any? { |h| h.variable_name.to_s.casecmp?(name) }
    end

    # El principal es el unico con "status" -- si por algun motivo ninguno lo
    # tiene (no deberia pasar, pero mejor no reventar), se usa el primer
    # archivo como principal y no se agrega ninguna seccion de loop.
    def build_consolidated_dictionary_rows(parsed_by_path)
      main_path, main_sheet = @sheets.find { |_path, sheet| variable?(sheet, STATUS_VARIABLE) } || @sheets.first
      rows = build_dictionary_rows(main_sheet.headers, parsed_by_path[main_path], main_sheet.rows)

      @sheets.each do |loop_path, loop_sheet|
        next if loop_path == main_path

        rows += [blank_dictionary_row, loop_section_title(main_path, loop_path)]
        rows += build_dictionary_rows(loop_sheet.headers, parsed_by_path[loop_path], loop_sheet.rows)
      end

      rows
    end

    # El nombre del loop se deriva del propio identificador que ya usa cada
    # worker para distinguir el archivo principal del/los loop(s) (ej.
    # "..._fichas.xlsx" vs "....xlsx" en Excel, o el nombre del .sps en
    # SPSS) -- no hace falta declararlo a mano.
    # File.basename(path, '.xlsx') solo quita esa extension puntual --
    # para un path de SPSS (".sps") no hacia nada, dejando el ".sps"
    # colgado en ambos *_base y por lo tanto nunca encontrando loop_base
    # como substring de main_base (confirmado con un export real de SPSS,
    # p573989981944: el titulo de la seccion de loop en el Diccionario
    # salia como el nombre de archivo completo en vez de un "Fichas"
    # limpio como ya sale bien en Excel). File.extname funciona para
    # cualquier extension, no solo xlsx.
    def loop_section_title(main_path, loop_path)
      main_base = File.basename(main_path.to_s, File.extname(main_path.to_s))
      loop_base = File.basename(loop_path.to_s, File.extname(loop_path.to_s))
      label = loop_base.sub(main_base, '').sub(/\A_/, '').presence || loop_base

      [label.titleize] + Array.new(DICTIONARY_HEADER.length - 1)
    end

    def blank_dictionary_row
      Array.new(DICTIONARY_HEADER.length)
    end

    # Si el schema de Confirmit tiene alguna forma inesperada para ESA
    # variable puntual (Nokogiri sobre datos reales, no hay garantia de
    # cubrir cada caso), el fallback es LabelParser directo sobre el label
    # ya compuesto que trae el propio export (evitando volver a pasar por el
    # lookup que rompio) -- una columna con un label mas simple es preferible
    # a perder el archivo entero.
    def resolve_headers(headers)
      headers.map { |header| resolve_header(header) }
    end

    def resolve_header(header)
      ExportRelabeling::VariableLabelResolver.call(variable_name: header.variable_name, raw_label: header.raw_label, lookup: @lookup)
    rescue StandardError => e
      Rails.logger.error("[ExportMetadataBuilder] resolucion de header #{header.variable_name} fallo, uso fallback: #{e.class} #{e.message}")
      ExportRelabeling::LabelParser.call(header.raw_label)
    end

    # Misma resolucion que las 3 filas de encabezado de Excel, pero en
    # formato tabla (una fila por variable) para que sea legible como
    # diccionario, en vez de tener que leer 3 filas columna por columna.
    # Suma las estadisticas por columna que pidio el cliente (ver
    # ExportRelabeling::ColumnStatistics) -- se calculan sobre los valores ya
    # presentes en este mismo archivo, no dependen de ninguna otra fuente.
    def build_dictionary_rows(headers, parsed, rows)
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
          format_answer_options(header.variable_name)
        ]
      end

      [DICTIONARY_HEADER] + entries
    end

    # Solo tiene contenido para preguntas Single (ver
    # ConfirmitVariableLookup#answer_options) -- una Multi ya muestra el
    # texto de su propia opcion en la columna "Atributo" de esa misma fila,
    # no hace falta repetirlo aca.
    def format_answer_options(variable_name)
      return nil unless @lookup

      options = safely("opciones de respuesta de #{variable_name}", []) { @lookup.answer_options(variable_name) }
      return nil if options.blank?

      options.map { |precode, text| "#{precode}=#{text}" }.join('; ')
    end
  end
end
