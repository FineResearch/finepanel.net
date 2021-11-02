class AddTitleToNewsFeeds < ActiveRecord::Migration[5.2]
  def change
    add_column :news_feeds, :title, :string
  end
end
