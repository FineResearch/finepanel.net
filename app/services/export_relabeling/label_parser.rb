# frozen_string_literal: true

# Separa un label crudo de export de Confirmit (VARIABLE LABELS/VALUE LABELS
# de un .sps, o header de un Excel) en {code, attribute, question}, para
# poder reescribirlo como "codigo | atributo | pregunta" sin depender del
# separador " (" ... ")" que usa Confirmit -- ese separador es fijo (no
# configurable, ni por CDL ni por la UI de Data Templates, confirmado
# probando `title:`/`label:` por variable en CDL contra un proyecto real)
# y choca cuando el propio texto de la pregunta tambien tiene parentesis.
#
# Opera sobre el string YA des-escapado (comillas simples SPSS `''` -> `'`),
# no sobre la linea cruda del .sps -- ese des-escapado es responsabilidad de
# quien lea el bloque VARIABLE LABELS/VALUE LABELS, no de esta clase.
#
# El piping sin resolver (^f('q0a')^, ^f('f15r')['1'].toNumber()^, incluso
# el condicional ^f('q0a').any('a')? 'x' : 'y'^) nunca se detecta ni se
# intenta resolver a proposito -- queda visible tal cual en el segmento que
# le toque, para que alguien lo revise a mano despues.
#
# Textos largos de consentimiento/legales (ej. "termo1"/"farmacovigilancia")
# pueden terminar en un parentesis que no tiene nada que ver con el patron
# "atributo (codigo - pregunta)" -- un marcador de lista tipo "(c)" o una
# aclaracion como "dezoito (18)". Confirmado contra un Excel real
# (p573989981944) que tratar cualquier parentesis final como valido rompe
# estos casos. Por eso un grupo final solo cuenta si tiene un " - " adentro
# (ver group_has_code_marker?); si no, se cae al fallback de texto completo,
# que a su vez solo separa codigo si el " - " aparece cerca del principio
# del string -- los codigos reales (F4, Q0a, TERMO1) siempre son un prefijo
# corto, nunca aparecen a mitad de un parrafo largo.
module ExportRelabeling
  class LabelParser
    # Los codigos reales vistos hasta ahora (F4, F9A, Q0a, TERMO1,
    # FARMACOVIGILANCIA) tienen come mucho ~20 caracteres -- 30 deja margen
    # sin ser tan laxo como para aceptar un " - " que en realidad esta a
    # mitad de un parrafo largo.
    MAX_CODE_MARKER_POSITION = 30

    def self.call(raw_label)
      new(raw_label).call
    end

    def self.reformat(raw_label)
      format(call(raw_label))
    end

    # Separado de reformat para que quien ya tenga un {code:, attribute:,
    # question:} resuelto por otra via (ej. ConfirmitVariableLookup, via
    # VariableLabelResolver) pueda armar el mismo string final sin volver a
    # parsear un raw_label.
    # parsed[:question] puede venir nil incluso cuando la variable SI se
    # encontro -- confirmado con variables Hidden armadas a mano (ej.
    # "LinkFarmaco") que la API resuelve a un Title/Text vacio de verdad,
    # no a un "no encontrado". Sin el `|| ''` esto devuelve nil, que
    # rompe a cualquier llamador que asuma un String (ej.
    # SpssSyntaxRewriter#escape_sps_string).
    def self.format(parsed)
      return parsed[:question] || '' if parsed[:code].nil? && parsed[:attribute].nil?

      "#{parsed[:code]} | #{parsed[:attribute]} | #{parsed[:question]}"
    end

    def initialize(raw_label)
      @raw_label = raw_label.to_s
    end

    def call
      group = last_top_level_group_at_end
      return fallback_split(@raw_label) unless group && group_has_code_marker?(group)

      attribute = @raw_label[0...group[:start]].strip
      code, question = split_code_and_question(@raw_label[(group[:start] + 1)...group[:end]])

      { code: code, attribute: attribute.empty? ? nil : attribute, question: question }
    end

    private

    def group_has_code_marker?(group)
      @raw_label[(group[:start] + 1)...group[:end]].include?(' - ')
    end

    # Escanea el string llevando profundidad de parentesis y devuelve el
    # ultimo grupo de "primer nivel" (el que vuelve a profundidad 0) que
    # termina exactamente en el ultimo caracter del string -- ese es el
    # grupo "codigo - pregunta" que Confirmit agrega siempre al final del
    # label. Los parentesis anidados adentro (o(a), Dr.(a), f('x'), etc.) no
    # generan grupos propios porque group_start solo se marca en depth == 0.
    # Si el string no termina en ")" (ej. piping condicional sin cierre),
    # devuelve nil y se cae al fallback de 2 partes.
    def last_top_level_group_at_end
      depth = 0
      group_start = nil
      last_group = nil

      @raw_label.each_char.with_index do |char, index|
        case char
        when '('
          group_start = index if depth.zero?
          depth += 1
        when ')'
          depth -= 1
          if depth.zero? && group_start
            last_group = { start: group_start, end: index }
            group_start = nil
          end
        end
      end

      return nil unless last_group && last_group[:end] == @raw_label.length - 1

      last_group
    end

    def split_code_and_question(text)
      code, sep, question = text.partition(' - ')
      return [nil, text.strip] if sep.empty?

      [code.strip.presence, question.strip]
    end

    def fallback_split(text)
      dash_index = text.index(' - ')
      return { code: nil, attribute: nil, question: text.strip } if dash_index.nil? || dash_index > MAX_CODE_MARKER_POSITION

      code, question = split_code_and_question(text)
      { code: code, attribute: nil, question: question }
    end
  end
end
