class SurveyBlueprint < Blueprinter::Base
  identifier :project_id, name: :id

  fields :name, :subject, :link

  field :duration do |survey|
    survey[:duration].try(:delete, ' minutos')
  end

  field :payment do |survey|
    survey[:fee].try(:delete, '$ A R MX USD COL BOL SOLES UY GUARANIES EUR .')
  end

end
