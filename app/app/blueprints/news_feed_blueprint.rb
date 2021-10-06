class NewsFeedBlueprint < Blueprinter::Base
  identifier :id

  fields :link

  field :alertDate do |news_feed|
    news_feed.set_alert_date
  end

  field :text do |news_feed|
    news_feed.set_text
  end

  field :type do |news_feed|
    news_feed.newsfeed_type
  end

  field :timeTag do |news_feed, options|
    news_feed.set_time_tag(options[:locale])
  end

  field :viewCount do |news_feed|
    news_feed.view_count
  end

  association :article, blueprint: ArticleBlueprint
end
