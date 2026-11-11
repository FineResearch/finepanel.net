# frozen_string_literal: true

# Una variable del cuestionario que ya se aviso como faltante en el export de un
# proyecto (ver ExportRelabeling::MissingVariablesDetector). Sirve para que el
# aviso interno salga UNA vez por proyecto y variable, y no en cada export diario
# mientras el PM no corrija el Data Template (Diego: "que solo se genere una
# sola vez por proyecto"). Si mas adelante falta una variable DISTINTA, esa si
# se avisa.
class ExportMissingVariableAlert < ApplicationRecord
  validates :project_id, presence: true
  validates :variable_name, presence: true

  # De los nombres dados, los que todavia NO se avisaron para ese proyecto
  # (se compara sin importar mayusculas, igual que el detector).
  def self.not_alerted(project_id, variable_names)
    already = where(project_id: project_id.to_s, variable_name: variable_names.map { |name| normalize(name) })
              .pluck(:variable_name)

    variable_names.reject { |name| already.include?(normalize(name)) }
  end

  # Marca como avisadas esas variables. Idempotente: si dos exports corren a la
  # vez, el indice unico deja pasar solo uno por variable y el otro se ignora.
  def self.register(project_id, variable_names)
    variable_names.each do |name|
      begin
        create!(project_id: project_id.to_s, variable_name: normalize(name))
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end
  end

  def self.normalize(name)
    name.to_s.strip.downcase
  end
end
