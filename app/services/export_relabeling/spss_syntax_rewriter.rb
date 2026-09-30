# frozen_string_literal: true

# Reescribe los labels compuestos (atributo+pregunta) dentro de los bloques
# VARIABLE LABELS y VALUE LABELS de una sintaxis SPSS (.sps), usando
# ExportRelabeling::LabelParser linea por linea -- deja todo lo demas del
# archivo intacto (FILE HANDLE, DATA LIST, los codigos de VALUE LABELS,
# variables de sistema sin patron detectable, labels de opciones simples
# como "Avastin (Bevacizumabe) + Quimioterapia" que no terminan en un grupo
# de parentesis de cierre, etc.).
#
# No hace falta modelar la estructura completa de cada bloque (donde
# empieza cada grupo de VALUE LABELS): tanto una entrada de VARIABLE LABELS
# ("NOMBRE 'label'") como una linea de codigo dentro de VALUE LABELS
# ("1 'label'" o "'a' 'label'") tienen la MISMA forma sintactica -- un
# token seguido de un string entre comillas simples -- asi que un solo
# regex + reemplazo alcanza para ambos casos, mientras se aplique solo
# dentro de los bloques correctos (delimitados por el header y el "."
# final, igual que el resto de la sintaxis SPSS).
#
# Si se le pasa un lookup (ConfirmitVariableLookup, ver
# VariableLabelResolver), se usa SOLO dentro de VARIABLE LABELS -- ahi el
# "token" de cada linea es un nombre de variable real, buscable en la API.
# Dentro de VALUE LABELS el "token" es un codigo de respuesta ('1', 'a'),
# no una variable, asi que esas lineas siguen usando unicamente LabelParser
# sobre el texto ya compuesto -- trackear en que variable esta cada bloque
# de VALUE LABELS para poder usar el lookup ahi tambien queda pendiente.
module ExportRelabeling
  class SpssSyntaxRewriter
    VARIABLE_LABELS_HEADER = 'VARIABLE LABELS'
    VALUE_LABELS_HEADER = 'VALUE LABELS'
    BLOCK_HEADERS = /\A(#{VARIABLE_LABELS_HEADER}|#{VALUE_LABELS_HEADER})\z/
    BLOCK_END = /\A\s*\.\s*\z/
    LABEL_LINE = /\A(\s*)(\S+)(\s+)'((?:[^']|'')*)'(\s*)\z/

    def self.call(sps_text, lookup: nil)
      new(sps_text, lookup).call
    end

    def initialize(sps_text, lookup = nil)
      @sps_text = sps_text
      @lookup = lookup
    end

    def call
      current_block = nil

      @sps_text.each_line.map do |line|
        stripped = line.chomp

        if (header_match = BLOCK_HEADERS.match(stripped))
          current_block = header_match[1]
          next line
        end

        if current_block && stripped.match?(BLOCK_END)
          current_block = nil
          next line
        end

        next line unless current_block

        rewrite_label_line(line, use_lookup: current_block == VARIABLE_LABELS_HEADER)
      end.join
    end

    private

    def rewrite_label_line(line, use_lookup:)
      trailing_newline = line.end_with?("\n") ? "\n" : ''
      match = LABEL_LINE.match(line.chomp)
      return line unless match

      leading, token, gap, escaped_label, trailing = match.captures
      raw_label = unescape_sps_string(escaped_label)
      parsed = ExportRelabeling::VariableLabelResolver.call(
        variable_name: token,
        raw_label: raw_label,
        lookup: use_lookup ? @lookup : nil
      )
      new_label = escape_sps_string(ExportRelabeling::LabelParser.format(parsed))

      "#{leading}#{token}#{gap}'#{new_label}'#{trailing}#{trailing_newline}"
    end

    def unescape_sps_string(text)
      text.gsub("''", "'")
    end

    # Un label resuelto via la API puede traer saltos de linea reales (ej.
    # "farmacovigilancia"/"termo1", textos legales con varios <p> en el
    # HTML de origen -- ver ConfirmitVariableLookup#clean_text) -- pero un
    # string entre comillas de SPSS no puede tener un salto de linea
    # literal adentro (rompe con "Unterminated string constant", confirmado
    # contra PSPP real). El .sps que exporta Confirmit siempre colapsa esos
    # saltos a un espacio simple (confirmado comparando el mismo texto en
    # el .sps crudo) -- se replica ese mismo criterio aca.
    def escape_sps_string(text)
      text.gsub(/\s+/, ' ').gsub("'", "''")
    end
  end
end
