class CreateNewsFeedTranslations < ActiveRecord::Migration[5.2]
  def change
    create_table :news_feed_translations do |t|
      t.references :news_feed, foreign_key: true
      t.integer :locale
      t.string :title
      t.text :text

      t.timestamps
    end
  end
end
