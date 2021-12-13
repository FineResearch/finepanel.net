class AddClosedToSurveyLinks < ActiveRecord::Migration[5.2]
  def change
    add_column :survey_links, :closed, :boolean, default: false
  end
end
