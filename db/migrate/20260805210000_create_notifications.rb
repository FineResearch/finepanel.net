class CreateNotifications < ActiveRecord::Migration[5.2]
  def change
    create_table :notifications do |t|
      t.references :user, foreign_key: true
      t.references :news_feed, foreign_key: true
      t.string :notification_type

      t.timestamps
    end

    add_index :notifications, [:user_id, :news_feed_id, :notification_type],
      unique: true, name: 'index_notifications_on_user_news_feed_and_type'
  end
end
