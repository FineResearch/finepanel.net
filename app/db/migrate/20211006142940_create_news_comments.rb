class CreateNewsComments < ActiveRecord::Migration[5.2]
  def change
    create_table :news_comments do |t|
      t.string :text
      t.references :user, foreign_key: true
      t.references :news_feed, foreign_key: true
      t.jsonb :user_info

      t.timestamps
    end
  end
end
