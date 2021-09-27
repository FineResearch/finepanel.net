class CreateNewsFeeds < ActiveRecord::Migration[5.2]
  def change
    create_table :news_feeds do |t|
      t.text :text
      t.string :link
      t.string :anchor
      t.datetime :alert_created_at
      t.string :update_type
      t.string :update_priority
      t.references :specialty, index: true, foreign_key: true
      t.references :article, index: true, foreign_key: true

      t.timestamps
    end
  end
end
