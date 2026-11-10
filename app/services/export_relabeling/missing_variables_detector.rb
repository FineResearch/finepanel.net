# frozen_string_literal: true

# Detecta preguntas del cuestionario que NO llegaron en el export -- el caso
# del acta del 06/11/2026 ("la Q5A no estaba": el PM arma a mano el Data
# Template de cada proyecto y a veces se le pasa una variable). Sirve para
# avisar a Fine (ver ProcessingAlertNotifier, nunca al cliente), que lo
# corrige agregandola al template.
#
# Solo se consideran las preguntas del cuestionario real, es decir las que
# estan entre PRESENTATION y iradatos1 en el schema (ver
# ConfirmitVariableLookup#questionnaire_variables), sin las Hidden: lo
# anterior es panel/sistema, lo posterior es cierre/control de duplicados, y
# las Hidden suele preferirse no exportarlas (Diego). Tampoco se avisan los
# textos legales (ver IGNORED_NAMES). Es el criterio de "es normal que falte".
#
# Una pregunta cuenta como presente si CUALQUIER archivo del export (el
# principal o un loop) tiene una columna que le corresponde: la propia
# variable, o una "<variable>_<algo>" (opcion de una Multi/Grid, "_other",
# fila de una Grid3D). Sin lookup, o si el schema no trae los marcadores,
# no se puede acotar el cuestionario y no se avisa nada -- una alerta con
# falsos positivos se termina ignorando.
module ExportRelabeling
  class MissingVariablesDetector
    START_MARKERS = %w[presentation presentacion].freeze
    END_MARKER = 'iradatos1'

    # Textos legales de consentimiento ("termo", "termo1"...,
    # "farmacovigilancia"): estan dentro del cuestionario pero no se exportan,
    # asi que avisarlos seria ruido en TODO proyecto (Diego: "excluilas").
    IGNORED_NAMES = [/\Atermo\d*\z/i, /\Afarmacovigilancia\z/i].freeze

    def self.call(lookup:, exported_names:)
      new(lookup, exported_names).call
    end

    def initialize(lookup, exported_names)
      @lookup = lookup
      @exported = Array(exported_names).map { |name| name.to_s.downcase }.uniq
    end

    # [{ name:, title: }, ...] en el orden del cuestionario; [] si no falta
    # nada o si no se pudo determinar.
    def call
      return [] unless @lookup

      units = @lookup.questionnaire_variables(start_markers: START_MARKERS, end_marker: END_MARKER)
      return [] if units.nil?

      units.reject { |unit| ignored?(unit) || exported?(unit) }.map { |unit| { name: unit[:name], title: unit[:title] } }
    end

    private

    def ignored?(unit)
      IGNORED_NAMES.any? { |pattern| unit[:name].to_s.match?(pattern) }
    end

    def exported?(unit)
      @exported.any? do |column|
        unit[:names].any? { |name| column == name || column.start_with?("#{name}_") }
      end
    end
  end
end
