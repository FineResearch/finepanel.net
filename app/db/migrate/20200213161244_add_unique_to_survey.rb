class AddUniqueConstraints < ActiveRecord::Migration[5.2]
  def change
    add_index :survey_links, [:project_id, :resp_id, :spanel, :link, :variables], unique: true, name: :unique_survey_links
  end
end
