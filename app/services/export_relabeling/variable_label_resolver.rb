# frozen_string_literal: true

# Punto unico donde se decide la fuente de un label: primero la API de
# Confirmit (ConfirmitVariableLookup, texto limpio y sin el bug de
# parentesis del motor de export), y si no la encuentra (variable de
# sistema, pregunta en un loop que el schema principal no trae, etc.) cae
# al parseo del texto ya compuesto del export (LabelParser).
#
# La API puede "encontrar" la variable pero resolverla a un Title/Text
# VACIO de verdad -- confirmado contra variables Hidden/de sistema reales
# (ej. "LinkFarmaco", "FechaCompleta", "timesurvey"), que existen en el
# schema pero nunca tuvieron texto configurado porque no se le muestran al
# respondiente. Un hash {question: nil/''} no es lo mismo que "no
# encontrado" (nil), pero tratarlo como valido borraba el label que el
# propio export YA traia -- Diego: "en esos casos es mejor mantener la
# referencia original en vez de sustituirla por blanco". Por eso un
# resultado de la API sin question usable se descarta igual que un "no
# encontrado", y se cae al fallback de texto crudo.
module ExportRelabeling
  class VariableLabelResolver
    def self.call(variable_name:, raw_label:, lookup: nil)
      resolved = lookup&.call(variable_name)
      return resolved if resolved && resolved[:question].present?

      LabelParser.call(raw_label)
    end
  end
end
