class NewsFeedBlueprint < Blueprinter::Base
  identifier :id

  fields :link

  field :alertDate do |news_feed|
    news_feed.alert_created_at.strftime("%d/%m/%Y")
  end

  field :text do |news_feed|
    news_feed.text.camelcase
  end

  field :type do |news_feed|
    return 'No Type' unless news_feed.article.present?
    type = news_feed.get_news_type
    type.present? ? type.capitalize : 'No Type'
  end

  field :timeTag do |news_feed|
    if news_feed.alert_created_at > 7.days.ago
      'last_week'
    elsif news_feed.alert_created_at > 30.days.ago
      'last_month'
    else
      'none'
    end
  end

  field :viewCount do |news_feed|
    news_feed.view_count
  end

  association :article, blueprint: ArticleBlueprint
  association :news_comments, blueprint: NewsCommentBlueprint
end
