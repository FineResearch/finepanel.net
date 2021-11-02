class NewsFeedBlueprint < Blueprinter::Base
  identifier :id

  fields :link

  field :alertDate do |news_feed|
    news_feed.alert_created_at.strftime("%d/%m/%Y")
  end

  field :title do |news_feed, options|
    if options[:locale].present? &&  %w{es pt}.include?(options[:locale])
      news_feed.news_feed_translations.send(options[:locale]).first.try(:title).try(:camelcase) || news_feed.title.try(:camelcase)
    else
      news_feed.title.try(:camelcase)
    end
  end

  field :text do |news_feed, options|
    if options[:locale].present? &&  %w{es pt}.include?(options[:locale])
      news_feed.news_feed_translations.send(options[:locale]).first.try(:text).try(:camelcase) || news_feed.text.try(:camelcase)
    else
      news_feed.text.try(:camelcase)
    end
  end

  field :type do |news_feed, options|
    return 'No Type' unless news_feed.article.present?
    type = news_feed.get_news_type
    type.present? ? I18n.with_locale(options[:locale]) { I18n.t("dynamed_content.articles_types.#{type}") } : 'No Type'
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

  association :news_comments, blueprint: NewsCommentBlueprint
end
