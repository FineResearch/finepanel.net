class AddFineNewsSummaryTranslationsToNewsFeeds < ActiveRecord::Migration[5.2]
  def change
    add_column :news_feeds, :fine_news_summary_translations, :jsonb, null: true
  end
end
