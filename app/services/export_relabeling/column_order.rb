# frozen_string_literal: true

# Ordena las columnas de un export de Confirmit segun el orden del CUESTIONARIO
# (Diego: "ordenemos siempre segun orden del cuestionario"). Confirmit exporta
# las columnas en el orden en que se crearon en la base, no en el del
# cuestionario -- en p378408306422 `s11x1b_2` caia en medio de `s11x1a_*`,
# `s11x3aa` dentro de `s12_*`, y `s4`/`s6` y `a3b`/`a4a` salian mezcladas. Con un
# solo criterio para Excel y SPSS (ver SpssDataListOrder), los dos formatos
# coinciden entre si.
#
# Solo se mueven las columnas que el schema reconoce (ver
# ConfirmitVariableLookup#column_position, que ademas solo reconoce lo que esta
# dentro de la carpeta "questionnaire"); las demas (variables de sistema,
# columnas de loops que el schema principal no trae, etc.) se quedan en el lugar
# donde estaban, y las reconocidas se reparten entre los lugares que ocupaban las
# reconocidas -- asi nada que no conocemos cambia de posicion.
#
# Mejora de mejor esfuerzo, como el resto del re-etiquetado: sin lookup, o si algo
# falla, se devuelve todo tal cual llego.
module ExportRelabeling
  class ColumnOrder
    # order[i] = indice ORIGINAL de la columna que va en el lugar i, o nil si no
    # hay nada que reordenar.
    def self.permutation(names, lookup)
      return nil unless lookup

      keys = names.map { |name| lookup.column_position(name) }
      known = keys.each_index.select { |index| keys[index] }
      return nil if known.length < 2

      sorted = known.sort_by { |index| [keys[index], index] }
      return nil if sorted == known

      order = (0...keys.length).to_a
      known.each_with_index { |slot, position| order[slot] = sorted[position] }
      order
    rescue StandardError => e
      Rails.logger.error("[ColumnOrder] no se pudo calcular el orden de columnas, se deja el original: #{e.class} #{e.message}")
      nil
    end

    def self.call(sheet, lookup)
      order = permutation(sheet.headers.map(&:variable_name), lookup)
      return sheet unless order

      new_index_of = {}
      order.each_with_index { |original, position| new_index_of[original] = position }

      ExcelReader::Sheet.new(
        sheet.name,
        order.map { |index| sheet.headers[index] },
        sheet.rows.map { |row| order.map { |index| row[index] } },
        remap_date_columns(sheet.date_columns, new_index_of)
      )
    end

    def self.remap_date_columns(date_columns, new_index_of)
      return date_columns if date_columns.blank?

      date_columns.map { |index| new_index_of[index] }
    end
    private_class_method :remap_date_columns
  end
end
