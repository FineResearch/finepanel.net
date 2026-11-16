# frozen_string_literal: true

# Reordena las variables del bloque DATA LIST de un .sps de Confirmit segun el
# orden del cuestionario (ver ColumnOrder) -- el SPSS queda en el mismo orden que
# el Excel. Cada variable del DATA LIST FIXED lleva sus columnas explicitas
# ("F9_1 65", "STATUS 9-28 (A)"), asi que cambiar el orden de las lineas cambia el
# orden de las variables del .sav SIN cambiar de donde se lee cada dato. El resto
# de la sintaxis (VARIABLE LABELS, VALUE LABELS...) refiere por nombre y no se toca.
#
# Sin lookup, sin bloque DATA LIST o sin nada que mover devuelve el texto tal cual.
module ExportRelabeling
  class SpssDataListOrder
    def self.call(sps_text, lookup)
      new(sps_text, lookup).call
    end

    def initialize(sps_text, lookup)
      @text = sps_text
      @lookup = lookup
    end

    def call
      return @text unless @lookup

      lines = @text.each_line.to_a
      slots = variable_line_indices(lines)
      names = slots.map { |index| SpssDataListReader::VARIABLE_DEF.match(lines[index].strip)[1] }
      order = ColumnOrder.permutation(names, @lookup)
      return @text unless order

      reordered = lines.dup
      slots.each_with_index { |slot, position| reordered[slot] = lines[slots[order[position]]] }
      reordered.join
    rescue StandardError => e
      Rails.logger.error("[SpssDataListOrder] no se pudo ordenar el DATA LIST, se deja el orden original: #{e.class} #{e.message}")
      @text
    end

    private

    # Indices de las lineas "NOMBRE inicio-fin" del primer bloque DATA LIST, con el
    # mismo criterio que SpssDataListReader#parse_data_list.
    def variable_line_indices(lines)
      start = lines.index { |line| line.strip.match?(SpssDataListReader::DATA_LIST_START) }
      return [] unless start

      indices = []
      ((start + 1)...lines.length).each do |index|
        stripped = lines[index].strip
        break if stripped.match?(SpssDataListReader::BLOCK_END)
        next if stripped.empty? || stripped.match?(SpssDataListReader::RECORD_MARKER) || stripped.match?(SpssDataListReader::SKIP_LINE)

        indices << index if SpssDataListReader::VARIABLE_DEF.match?(stripped)
      end
      indices
    end
  end
end
