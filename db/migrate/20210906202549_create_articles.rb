class CreateArticles < ActiveRecord::Migration[5.2]
  def change
    create_table :articles do |t|
      t.string :dynamed_id
      t.string :title
      t.string :slug
      t.references :specialty, foreign_key: true

      t.timestamps
    end
    add_index :articles, :dynamed_id
  end
end
