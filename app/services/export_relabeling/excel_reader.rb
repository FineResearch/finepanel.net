# frozen_string_literal: true

require 'zip'
require 'nokogiri'
require 'set'

# Lee un .xlsx real de Confirmit sin pasar por rubyXL -- confirmado contra
# un archivo real (p573989981944) que rubyXL no puede abrir porque
# workbook.xml usa el namespace principal con prefijo ("<x:workbook
# xmlns:x=...>", en vez de sin prefijo) y el parser de rubyXL no lo
# reconoce. Nokogiri + remove_namespaces! no tiene ese problema (no le
# importa el prefijo), asi que se usa directo sobre el XML interno del
# xlsx en vez de depender de una gema de alto nivel para la lectura.
#
# Confirmado tambien contra ese archivo real: no hay sharedStrings.xml
# (todos los valores son inline, t="str", directo en <v>), y la fila de
# encabezados viene como "nombre_variable : label" -- el label de ahi en
# adelante tiene el mismo problema de parentesis que el .sps, resoluble
# con el mismo ExportRelabeling::LabelParser ya probado.
#
# Las preguntas de tipo fecha (ej. "Q11" del loop de fichas) NO vienen
# como texto -- Confirmit las deja como el numero de serie de Excel (ej.
# "45847") con un estilo de celda que aplica formato de fecha (numFmtId
# built-in 14) -- confirmado contra el .xlsx real de fichas. Si no se
# preserva esa info, el .xlsx final (armado desde cero, sin estilos) las
# muestra como el numero crudo en vez de una fecha -- por eso se detectan
# aca las columnas de fecha (por estilo de celda, no por nombre de
# variable) para que ExcelWriter les reaplique el formato.
module ExportRelabeling
  class ExcelReader
    Sheet = Struct.new(:name, :headers, :rows, :date_columns)
    Header = Struct.new(:variable_name, :raw_label)

    # IDs de formato de fecha/hora que trae Excel de fabrica (built-in,
    # ECMA-376) -- no requieren una entrada propia en <numFmts>, por eso no
    # alcanza con mirar los formatos personalizados.
    DATE_TIME_BUILTIN_IDS = ((14..22).to_a + (45..47).to_a).freeze
    DATE_FORMAT_TOKEN = /[dmyhs]/i.freeze

    def self.call(xlsx_path)
      new(xlsx_path).call
    end

    def initialize(xlsx_path)
      @xlsx_path = xlsx_path
      @entries = {}
    end

    def call
      Zip::File.open(@xlsx_path) do |zip|
        zip.each { |entry| @entries[entry.name] = entry.get_input_stream.read }
      end

      sheet_name, worksheet_entry = resolve_sheet
      worksheet_doc = xml_for(worksheet_entry)
      header_cells, *data_rows_nodes = worksheet_doc.xpath('//row')

      raise "El .xlsx no tiene filas: #{@xlsx_path}" unless header_cells

      headers = parse_headers(header_cells)
      column_count = headers.length
      rows = data_rows_nodes.map { |row_node| parse_row(row_node, column_count) }
      date_columns = date_columns_in(data_rows_nodes, column_count)

      Sheet.new(sheet_name, headers, rows, date_columns)
    end

    private

    # Una columna se marca "de fecha" si ALGUNA celda de datos usa un
    # estilo con formato de fecha -- no hace falta que las 40 mil filas lo
    # tengan, alcanza con una para saber que esa columna es de ese tipo.
    def date_columns_in(row_nodes, column_count)
      date_style_ids = date_style_ids_from_styles
      return [] if date_style_ids.empty?

      columns = Set.new
      row_nodes.each do |row_node|
        row_node.xpath('./c').each do |cell|
          style_id = cell['s']
          next unless style_id && date_style_ids.include?(style_id.to_i)

          index = column_index(cell['r'])
          columns << index if index && index < column_count
        end
      end

      columns.to_a
    end

    # xl/styles.xml no siempre esta presente (ej. un .xlsx armado a mano
    # sin ninguna celda con estilo) -- en ese caso no hay columnas de fecha
    # que detectar, no es un error.
    def date_style_ids_from_styles
      content = @entries['xl/styles.xml']
      return Set.new unless content

      doc = Nokogiri::XML(content)
      doc.remove_namespaces!

      custom_formats = doc.xpath('//numFmts/numFmt').each_with_object({}) do |node, acc|
        acc[node['numFmtId'].to_i] = node['formatCode']
      end

      date_ids = Set.new
      doc.xpath('//cellXfs/xf').each_with_index do |xf, index|
        date_ids << index if date_format?(xf['numFmtId'].to_i, custom_formats)
      end

      date_ids
    end

    def date_format?(num_fmt_id, custom_formats)
      return true if DATE_TIME_BUILTIN_IDS.include?(num_fmt_id)

      code = custom_formats[num_fmt_id]
      return false unless code

      stripped = code.gsub(/"[^"]*"/, '').gsub(/\[[^\]]*\]/, '')
      DATE_FORMAT_TOKEN.match?(stripped)
    end

    def xml_for(entry_name)
      content = @entries[entry_name]
      raise "No se encontro #{entry_name} dentro del xlsx" unless content

      doc = Nokogiri::XML(content)
      doc.remove_namespaces!
      doc
    end

    def resolve_sheet
      sheet_node = xml_for('xl/workbook.xml').at_xpath('//sheet')
      raise 'No se encontro ninguna hoja en el workbook' unless sheet_node

      rel_id = sheet_node['id']
      rel_node = xml_for('xl/_rels/workbook.xml.rels').at_xpath("//Relationship[@Id='#{rel_id}']")
      raise "No se encontro la relacion #{rel_id}" unless rel_node

      worksheet_entry = rel_node['Target'].sub(%r{\A/}, '')
      [sheet_node['name'], worksheet_entry]
    end

    def parse_headers(header_row_node)
      header_row_node.xpath('./c').map do |cell|
        raw = cell_value(cell).to_s
        variable_name, separator, raw_label = raw.partition(' : ')
        separator.empty? ? Header.new(variable_name, variable_name) : Header.new(variable_name, raw_label)
      end
    end

    # Las filas de datos pueden omitir celdas vacias (el XML no siempre
    # trae un <c> por cada columna) -- se alinean por la referencia de
    # columna de cada celda (ej. "C5" -> indice 2), no por orden de
    # aparicion, para no desalinear columnas cuando faltan celdas.
    def parse_row(row_node, column_count)
      values = Array.new(column_count)

      row_node.xpath('./c').each do |cell|
        index = column_index(cell['r'])
        next if index.nil? || index >= column_count

        values[index] = cell_value(cell)
      end

      values
    end

    def cell_value(cell)
      cell.at_xpath('./v')&.text
    end

    def column_index(cell_reference)
      return nil unless cell_reference

      letters = cell_reference[/[A-Z]+/]
      return nil unless letters

      letters.chars.reduce(0) { |acc, char| (acc * 26) + (char.ord - 'A'.ord + 1) } - 1
    end
  end
end
