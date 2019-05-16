class AddVariablesToSurveyLink < ActiveRecord::Migration[5.2]
  def change
    add_column :survey_links, :variables, :string
  end
end
