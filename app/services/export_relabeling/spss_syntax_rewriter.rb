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
# VariableLabelResolver), se usa dentro de VARIABLE LABELS -- ahi el "token" de
# cada linea es un nombre de variable real, buscable en la API. Dentro de VALUE
# LABELS el "token" es un codigo de respuesta ('1', 'a'), asi que esas lineas
# usan LabelParser sobre el texto ya compuesto, con una excepcion: la casilla
# marcada de una pregunta de respuesta multiple se reemplaza por su atributo (ver
# #selected_option_label), para lo que se trackea en que variable esta cada
# sub-bloque de VALUE LABELS.
module ExportRelabeling
  class SpssSyntaxRewriter
    VARIABLE_LABELS_HEADER = 'VARIABLE LABELS'
    VALUE_LABELS_HEADER = 'VALUE LABELS'
    BLOCK_HEADERS = /\A(#{VARIABLE_LABELS_HEADER}|#{VALUE_LABELS_HEADER})\z/
    BLOCK_END = /\A\s*\.\s*\z/
    LABEL_LINE = /\A(\s*)(\S+)(\s+)'((?:[^']|'')*)'(\s*)\z/
    # En VALUE LABELS cada sub-bloque arranca con una linea que es SOLO el nombre de la
    # variable (" S91_1"), seguida de sus lineas de codigo ("  1 'label'") y cerrada
    # con " /".
    VALUE_LABELS_VARIABLE_LINE = /\A\s*([^\s\/'][^\s']*)\s*\z/
    # SPSS trunca un value label a 120 bytes (PSPP avisa "Truncating value label").
    MAX_VALUE_LABEL_BYTES = 120

    # SPSS corta el label de una variable alrededor de 250 caracteres (el
    # cliente lo menciono en la reunion del 06/11/2026) -- se limita en BYTES
    # (un acento ocupa 2 en UTF-8) para no pasarse nunca. Se corta por el
    # FINAL a proposito: el formato de LabelFormatter pone el atributo antes
    # que la pregunta justamente para que lo que se pierda sea el final del
    # texto largo de la pregunta y no lo que identifica a la columna.
    MAX_VARIABLE_LABEL_BYTES = 250

    def self.call(sps_text, lookup: nil)
      new(sps_text, lookup).call
    end

    def initialize(sps_text, lookup = nil)
      @sps_text = sps_text
      @lookup = lookup
    end

    def call
      current_block = nil
      @value_variable = nil

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

        track_value_labels_variable(stripped) if current_block == VALUE_LABELS_HEADER
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
      new_label = escape_sps_string(selected_option_label(token, use_lookup) || build_label(token, parsed, use_lookup))

      "#{leading}#{token}#{gap}'#{new_label}'#{trailing}#{trailing_newline}"
    end

    def track_value_labels_variable(stripped)
      if (match = VALUE_LABELS_VARIABLE_LINE.match(stripped))
        @value_variable = match[1]
      elsif stripped.strip == '/'
        @value_variable = nil
      end
    end

    # Pregunta de respuesta multiple (RM): Confirmit etiqueta la casilla marcada (1) con
    # el MISMO texto compuesto que la variable ("S9.1 - pregunta (Melanoma)"), que quedaba
    # en el layout viejo con el atributo al final. Para una RM el value label es solo el
    # atributo -- "Melanoma" -- porque la pregunta ya esta en el label de la variable
    # (FP-18918N). Solo con schema (hay que saber que es una RM y cual es su atributo);
    # sin eso queda como estaba.
    def selected_option_label(code, variable_labels_block)
      return nil if variable_labels_block || @lookup.nil? || @value_variable.nil? || code != '1'

      profile = @lookup.column_profile(@value_variable)
      return nil unless profile && profile[:type] == :multi

      attribute = @lookup.call(@value_variable)&.dig(:attribute).to_s.gsub(/\s+/, ' ').strip
      return nil if attribute.empty?

      truncate_bytes(attribute, MAX_VALUE_LABEL_BYTES)
    end

    # VARIABLE LABELS: el mismo texto que el encabezado del Excel ("VARIABLE :
    # atributo | TITULO. pregunta", ver LabelFormatter), truncado por el final.
    # VALUE LABELS: la etiqueta de una opcion de respuesta, sin variable que
    # anteponer -- queda como estaba.
    def build_label(token, parsed, variable_labels_block)
      return ExportRelabeling::LabelParser.format(parsed) unless variable_labels_block

      label = ExportRelabeling::LabelFormatter.call(variable_name: token, parsed: parsed)
      # Una variable sin texto (ej. RESPONSEID '') queda como estaba, no con su
      # propio nombre repetido como label.
      return parsed[:question].to_s if label.casecmp?(token.to_s)

      truncate_bytes(label)
    end

    def truncate_bytes(text, limit = MAX_VARIABLE_LABEL_BYTES)
      return text if text.bytesize <= limit

      text.byteslice(0, limit).scrub('').strip
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
