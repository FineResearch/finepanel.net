# frozen_string_literal: true

# Arma UNA fila del Dictionary (una variable exportada) con el formato del
# modelo del cliente (acta del 06/11/2026):
#
#   Variable | Code | Attribute | Question | Mean | Min | Max | Nulls |
#   % Nulls | Zeros | Type | Answer Options
#
# - Code: el titulo de la pregunta (F0, I3, D1a), no el precode de una
#   respuesta. Para las preguntas Single/Multi que antes quedaban vacias, ahora
#   se completa siempre que la API lo resuelva.
# - Type: Single / Multi / Numeric / Text / Date / "N-point scale". Sale del
#   schema de Confirmit (ConfirmitVariableLookup#column_profile); si la variable
#   no esta en el schema (sistema, loop que el schema principal no trae) se
#   deduce de los datos de la propia columna -- una columna sin valores queda
#   en "-", sin inventar un tipo.
# - Mean/Min/Max solo para Numeric; Zeros no aplica a Text/Date ni a una
#   columna con valores no numericos. Nulls y % Nulls siempre.
# - Lo que no aplica se muestra "-" (igual que el modelo del cliente), no
#   una celda vacia que parezca un dato faltante.
#
# El texto fijo orientado al cliente va en ingles (decision de Diego).
module ExportRelabeling
  class DictionaryEntryBuilder
    EMPTY = '-'
    OPTION_SEPARATOR = ' | '
    MULTI_OPTIONS = '0 = Not selected | 1 = Selected'

    TYPE_NAMES = {
      single: 'Single', multi: 'Multi', numeric: 'Numeric', date: 'Date', text: 'Text', other_text: 'Text'
    }.freeze

    def self.call(variable_name:, parsed:, values:, profile: nil)
      new(variable_name, parsed, values, profile).call
    end

    def initialize(variable_name, parsed, values, profile)
      @variable_name = variable_name
      @parsed = parsed || {}
      @values = values
      @profile = profile
      @stats = ExportRelabeling::ColumnStatistics.call(values)
    end

    def call
      [
        @variable_name,
        present_or_dash(@parsed[:code]),
        present_or_dash(@parsed[:attribute]),
        present_or_dash(@parsed[:question]),
        numeric_stat(:mean), numeric_stat(:min), numeric_stat(:max),
        @stats[:null_count],
        @stats[:null_percentage],
        zeros,
        type_name,
        answer_options
      ]
    end

    private

    def kind
      @kind ||= @profile ? @profile[:type] : inferred_kind
    end

    # Sin schema: solo se afirma lo que los datos demuestran.
    def inferred_kind
      return nil if non_blank_values.empty?

      all_numeric? ? :numeric : :text
    end

    def non_blank_values
      @non_blank_values ||= @values.reject { |value| value.nil? || value.to_s.strip.empty? }
    end

    def all_numeric?
      non_blank_values.all? { |value| numeric?(value) }
    end

    def numeric?(value)
      Float(value)
      true
    rescue ArgumentError, TypeError
      false
    end

    def type_name
      return EMPTY if kind.nil?
      return scale_type_name if kind == :scale

      TYPE_NAMES.fetch(kind, EMPTY)
    end

    # Si el schema no permitio resolver los puntos, mejor "Scale" a secas que
    # un "0-point scale" que es un dato falso.
    def scale_type_name
      points = @profile[:scale_points].to_i
      points.positive? ? "#{points}-point scale" : 'Scale'
    end

    def numeric_stat(key)
      kind == :numeric ? (@stats[key].nil? ? EMPTY : @stats[key]) : EMPTY
    end

    def zeros
      return EMPTY if kind.nil? || %i[text other_text date].include?(kind)
      return EMPTY unless all_numeric?

      @stats[:zero_count]
    end

    def answer_options
      case kind
      when :single then format_options(@profile[:options])
      when :multi then MULTI_OPTIONS
      when :scale then scale_options
      when :numeric then 'Numeric value'
      when :date then 'Date'
      when :text then 'Open text'
      when :other_text then "Open text linked to #{@profile[:linked_to]}"
      else EMPTY
      end
    end

    # Una escala sin etiquetas por punto igual se explica por sus numeros.
    def scale_options
      return format_options(@profile[:options]) if @profile[:options].present?

      format_options((1..@profile[:scale_points]).map { |point| [point.to_s, point.to_s] })
    end

    def format_options(options)
      return EMPTY if options.blank?

      options.map { |precode, text| "#{precode} = #{text}" }.join(OPTION_SEPARATOR)
    end

    def present_or_dash(text)
      text.to_s.strip.empty? ? EMPTY : text
    end
  end
end
