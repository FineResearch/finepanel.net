# frozen_string_literal: true

# Punto unico donde se decide la fuente de un label: primero la API de
# Confirmit (ConfirmitVariableLookup, texto limpio y sin el bug de
# parentesis del motor de export), y si no la encuentra (variable de
# sistema, pregunta en un loop que el schema principal no trae, etc.) cae
# al parseo del texto ya compuesto del export (LabelParser).
module ExportRelabeling
  class VariableLabelResolver
    def self.call(variable_name:, raw_label:, lookup: nil)
      lookup&.call(variable_name) || LabelParser.call(raw_label)
    end
  end
end
