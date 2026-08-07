class CreateNewsFeedReactions < ActiveRecord::Migration[5.2]
  def change
    create_table :news_feed_reactions do |t|
      t.references :user, foreign_key: true
      t.references :news_feed, foreign_key: true
      t.boolean :useful, null: false

      t.timestamps
    end

    add_index :news_feed_reactions, [:user_id, :news_feed_id],
      unique: true, name: 'index_news_feed_reactions_on_user_and_news_feed'
  end
end
