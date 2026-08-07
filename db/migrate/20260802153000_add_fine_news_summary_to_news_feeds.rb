class AddFineNewsSummaryToNewsFeeds < ActiveRecord::Migration[5.2]
  def change
    add_column :news_feeds, :fine_news_summary, :jsonb, null: true
  end
end
