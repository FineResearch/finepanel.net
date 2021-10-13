class AddCountToNewsFeed < ActiveRecord::Migration[5.2]
  def change
    add_column :news_feeds, :view_count, :integer, default: 0, null: false
  end
end
