# frozen_string_literal: true

# Arma un crosstab simple (conteo de casos por combinacion) para las lineas
# de la seccion "Report:" del mail (ver ManualQuotaRequestParser) -- a
# diferencia de "Quotas:", esto NO controla contra ninguna meta, solo
# presenta cuantos casos completos hay para cada combinacion real que
# aparece en los datos.
#
# Mismo criterio de fuente que QuotaProgressBuilder: las 2 variables tienen
# que vivir en el MISMO archivo (principal o el mismo loop) para poder
# cruzarlas -- una fila de loop no tiene 1:1 con un entrevistado, asi que
# no hay forma de cruzar una variable del principal con una del loop.
#
# El titulo de cada tabla ("variable_a x variable_b") se resalta en negrita
# + fondo amarillo (a pedido de Diego) -- por eso #call devuelve
# { rows:, header_indices: } en vez de un array plano, con header_indices
# apuntando a esas filas de titulo. La fila vieja "variable_a \ variable_b"
# (redundante con el titulo) ya no se escribe -- la esquina de la tabla de
# valores queda en blanco.
#
# Cada tabla suma una columna "Total" (a la derecha, suma de la fila) y una
# fila "Total" (abajo, suma de la columna -- la celda inferior derecha es el
# gran total de la tabla) -- ver #crosstab_rows.
module ExportRelabeling
  class CrosstabBuilder
    NOT_FOUND = 'variable not found in any exported file'
    CROSS_SOURCE_UNSUPPORTED = 'variables in different files -- cannot be crossed'
    TOTAL_LABEL = 'Total'

    # sources: mismo formato que QuotaProgressBuilder -- array de
    # { headers:, rows:, status_variable:, complete_value: }.
    def self.call(crosses:, sources:)
      new(crosses, sources).call
    end

    def initialize(crosses, sources)
      @crosses = crosses
      @sources = sources
    end

    def call
      rows = []
      header_indices = []

      @crosses.each_with_index do |cross, index|
        rows << [] unless index.zero?
        header_indices << rows.length
        rows.concat(build_table(cross))
      end

      { rows: rows, header_indices: header_indices }
    end

    private

    def build_table(cross)
      title = "#{cross[:variable_a]} x #{cross[:variable_b]}"
      source_a = source_for(cross[:variable_a])
      source_b = source_for(cross[:variable_b])

      return [[title], [NOT_FOUND]] if source_a.nil? || source_b.nil?
      return [[title], [CROSS_SOURCE_UNSUPPORTED]] unless source_a == source_b

      [[title]] + crosstab_rows(source_a, cross[:variable_a], cross[:variable_b])
    end

    # Ademas del cruce, agrega una columna "Total" (suma de la fila) y una
    # fila "Total" (suma de la columna, mas el gran total abajo a la
    # derecha) -- a pedido de Diego, para no tener que sumar a mano cada
    # tabla.
    def crosstab_rows(source, variable_a, variable_b)
      idx_a = header_index(source, variable_a)
      idx_b = header_index(source, variable_b)
      status_idx = header_index(source, source[:status_variable])

      values_a = distinct_values(source, idx_a, status_idx)
      values_b = distinct_values(source, idx_b, status_idx)

      counts = values_a.map { |value_a| values_b.map { |value_b| count(source, idx_a, value_a, idx_b, value_b, status_idx) } }

      header_row = [nil] + values_b + [TOTAL_LABEL]
      body_rows = values_a.each_with_index.map { |value_a, i| [value_a] + counts[i] + [counts[i].sum] }
      column_totals = values_b.each_index.map { |j| counts.sum { |row| row[j] } }
      total_row = [TOTAL_LABEL] + column_totals + [column_totals.sum]

      [header_row] + body_rows + [total_row]
    end

    def distinct_values(source, idx, status_idx)
      source[:rows]
        .select { |data_row| status_idx.nil? || complete?(data_row[status_idx], source) }
        .map { |data_row| data_row[idx] }
        .compact
        .uniq
        .sort
    end

    def count(source, idx_a, value_a, idx_b, value_b, status_idx)
      source[:rows].count do |data_row|
        next false if status_idx && !complete?(data_row[status_idx], source)

        data_row[idx_a] == value_a && data_row[idx_b] == value_b
      end
    end

    def complete?(status_value, source)
      status_value.to_s.casecmp?(source[:complete_value].to_s)
    end

    def source_for(variable_name)
      @sources.find { |source| header_index(source, variable_name) }
    end

    def header_index(source, variable_name)
      return nil if variable_name.blank?

      source[:headers].find_index { |header| header.variable_name.to_s.casecmp?(variable_name) }
    end
  end
end
