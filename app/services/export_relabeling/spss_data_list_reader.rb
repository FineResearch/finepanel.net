# frozen_string_literal: true

# Lee un par .sps+.dat de Confirmit y arma la misma forma
# ExportRelabeling::ExcelReader::Sheet { name, headers, rows, date_columns }
# que ya usa el pipeline de Excel para Dictionary/Quotas/Report -- asi
# ExportRelabeling::ExportMetadataBuilder no necesita saber si la fuente
# original era un .xlsx o un .sps+.dat (ver RelabelSpssExportWorker).
#
# El bloque DATA LIST de Confirmit siempre viene con esta forma (confirmado
# contra 2+ archivos reales, ej. p833174000229):
#
#   DATA LIST
#    FIXED FILE = F8321703
#    RECORDS=1
#   /1
#    RESPONSEID 1-8
#    STATUS 9-28 (A)
#    RESPID 29-36
#   .
#
# Solo se soporta un unico record ("/1") -- nunca se vio un .sps real de
# Confirmit con mas de uno, y RECORDS siempre viene en 1. Si algun dia
# aparece un caso con mas, esto simplemente no encuentra columnas despues
# del primer marcador "/2" (las ignora), no revienta -- queda a cargo del
# llamador decidir que hacer si el resultado viene corto/vacio.
module ExportRelabeling
  class SpssDataListReader
    DATA_LIST_START = /\ADATA LIST\z/i.freeze
    VARIABLE_LABELS_START = /\AVARIABLE LABELS\z/i.freeze
    BLOCK_END = /\A\.\z/.freeze
    RECORD_MARKER = /\A\/\d+\z/.freeze
    SKIP_LINE = /\A(FIXED|RECORDS)\b/i.freeze
    VARIABLE_DEF = /\A(\S+)\s+(\d+)-(\d+)(?:\s*\([^)]*\))?\z/.freeze
    LABEL_LINE = /\A(\S+)\s+'((?:[^']|'')*)'\z/.freeze

    def self.call(sps_text:, data_path:)
      new(sps_text, data_path).call
    end

    def initialize(sps_text, data_path)
      @lines = sps_text.to_s.each_line.map { |l| l.strip }
      @data_path = data_path
    end

    def call
      columns = parse_data_list
      raise 'No se encontro ningun campo en el bloque DATA LIST' if columns.empty?

      raw_labels = parse_variable_labels
      headers = columns.map { |c| ExcelReader::Header.new(c[:name], raw_labels[c[:name].downcase] || c[:name]) }
      rows = read_rows(columns)

      ExcelReader::Sheet.new(nil, headers, rows, [])
    end

    private

    def parse_data_list
      start_idx = @lines.index { |l| l.match?(DATA_LIST_START) }
      return [] unless start_idx

      columns = []
      @lines[(start_idx + 1)..-1].each do |line|
        break if line.match?(BLOCK_END)
        next if line.empty? || line.match?(RECORD_MARKER) || line.match?(SKIP_LINE)

        match = VARIABLE_DEF.match(line)
        columns << { name: match[1], start: match[2].to_i, end: match[3].to_i } if match
      end
      columns
    end

    def parse_variable_labels
      start_idx = @lines.index { |l| l.match?(VARIABLE_LABELS_START) }
      return {} unless start_idx

      labels = {}
      @lines[(start_idx + 1)..-1].each do |line|
        break if line.match?(BLOCK_END)

        match = LABEL_LINE.match(line)
        labels[match[1].downcase] = match[2].gsub("''", "'") if match
      end
      labels
    end

    # Posiciones de columna 1-indexed e inclusivas (convencion SPSS) -- se
    # convierten a un slice 0-indexed de Ruby. .strip saca el padding de
    # espacios que SPSS usa para rellenar columnas de ancho fijo (nunca
    # saca espacios REALES del medio de un valor, solo los de las puntas,
    # que es exactamente el padding).
    def read_rows(columns)
      File.readlines(@data_path, encoding: 'bom|utf-8').map do |line|
        chomped = line.chomp
        columns.map { |c| chomped[(c[:start] - 1)...c[:end]].to_s.strip }
      end
    end
  end
end
