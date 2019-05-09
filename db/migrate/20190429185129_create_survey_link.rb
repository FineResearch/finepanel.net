class CreateSurveyLink < ActiveRecord::Migration[5.2]
  def change
    create_table :survey_links do |t|
      t.string :project_id, null: false, default: ""
      t.string :resp_id, null: false, default: ""
      t.string :spanel, null: false, default: ""
      t.string :link, null: false, default: ""

      t.timestamps
    end
  end
end
