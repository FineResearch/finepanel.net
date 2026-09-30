# frozen_string_literal: true

require 'rubyXL'
require 'rubyXL/convenience_methods'

# Escribe el .xlsx final -- a diferencia de la lectura (ver ExcelReader),
# acá no hay problema de compatibilidad con rubyXL porque el XML lo
# generamos nosotros desde cero, no dependemos de parsear el de Confirmit.
module ExportRelabeling
  class ExcelWriter
    # Mismo criterio que usaba Confirmit (numFmtId built-in 14) para las
    # columnas de fecha detectadas por ExcelReader -- sin esto, el valor
    # (el numero de serie de Excel, ej. "45847") se ve tal cual, sin pinta
    # de fecha, en el archivo final armado desde cero.
    DATE_FORMAT = 'dd/mm/yyyy'

    # Estilo de las filas de encabezado repetidas en cada bloque de las
    # hojas "Quotas"/"Report" (ver QuotaProgressBuilder/CrosstabBuilder) --
    # negrita + fondo amarillo, a pedido de Diego.
    HIGHLIGHT_FILL = 'FFFF00'

    # header_rows: array de arrays (una fila por elemento -- 3 filas para
    # codigo/atributo/pregunta). data_rows: array de arrays con los valores
    # ya filtrados. extra_sheets: opcional, Hash ordenado {nombre_hoja =>
    # spec} -- una hoja mas por cada entrada, en el orden en que vengan en
    # el Hash. `spec` puede ser directamente un array de arrays (sin
    # resaltado), o un Hash { rows:, highlighted_rows: [indices] } cuando
    # ademas hay que resaltar filas puntuales en negrita + fondo amarillo
    # (ej. los encabezados repetidos de "Quotas"/"Report"). date_columns:
    # opcional, indices (0-based) de columnas de @data_rows que deben verse
    # como fecha, no como el numero de serie crudo.
    def self.call(sheet_name:, header_rows:, data_rows:, output_path:, extra_sheets: {}, date_columns: [])
      new(sheet_name, header_rows, data_rows, output_path, extra_sheets, date_columns).call
    end

    def initialize(sheet_name, header_rows, data_rows, output_path, extra_sheets, date_columns)
      @sheet_name = sheet_name.presence || 'Sheet1'
      @header_rows = header_rows
      @data_rows = data_rows
      @output_path = output_path
      @extra_sheets = extra_sheets || {}
      @date_columns = date_columns || []
    end

    def call
      workbook = RubyXL::Workbook.new
      write_data_sheet(workbook.worksheets[0])
      @extra_sheets.each { |name, spec| write_extra_sheet(workbook, name, spec) if extra_sheet_rows(spec).present? }

      workbook.write(@output_path)
      @output_path
    end

    private

    def write_data_sheet(sheet)
      sheet.sheet_name = @sheet_name
      write_rows(sheet, @header_rows, 0)
      write_rows(sheet, @data_rows, @header_rows.length, date_columns: @date_columns)
    end

    def extra_sheet_rows(spec)
      spec.is_a?(Hash) ? spec[:rows] : spec
    end

    def write_extra_sheet(workbook, name, spec)
      rows = extra_sheet_rows(spec)
      highlighted_rows = spec.is_a?(Hash) ? Array(spec[:highlighted_rows]) : []

      sheet = workbook.add_worksheet(name)
      write_rows(sheet, rows, 0)
      highlighted_rows.each { |row_idx| highlight_row(sheet, row_idx, rows[row_idx]) }
    end

    def highlight_row(sheet, row_idx, row)
      return unless row

      row.each_index do |col_idx|
        cell = sheet[row_idx]&.[](col_idx)
        next unless cell

        cell.change_font_bold(true)
        cell.change_fill(HIGHLIGHT_FILL)
      end
    end

    # Los valores de ExcelReader son siempre String (asi vienen del XML
    # crudo) -- rubyXL escribe un String como texto (t="str"), y Excel
    # ignora cualquier formato de numero en una celda de texto, sin
    # importar el estilo que tenga (confirmado: el estilo de fecha SI
    # quedaba aplicado, pero la celda seguia mostrando el numero crudo
    # porque Excel nunca le aplica formato a texto). Para que el formato de
    # fecha realmente funcione hay que escribir el numero de serie como
    # numero, no como string -- por eso una columna de fecha convierte el
    # valor antes de escribirlo.
    def write_rows(sheet, rows, row_offset, date_columns: [])
      rows.each_with_index do |row, row_idx|
        row.each_with_index do |value, col_idx|
          is_date_column = date_columns.include?(col_idx)
          cell_value = is_date_column ? numeric_or(value) : value
          cell = sheet.add_cell(row_idx + row_offset, col_idx, cell_value)
          cell.set_number_format(DATE_FORMAT) if value.present? && is_date_column
        end
      end
    end

    def numeric_or(value)
      return value if value.blank?

      numeric = Float(value)
      numeric.to_i == numeric ? numeric.to_i : numeric
    rescue ArgumentError, TypeError
      value
    end
  end
end
