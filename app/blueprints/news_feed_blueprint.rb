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

  field :usefulCount do |news_feed|
    news_feed.news_feed_reactions.where(useful: true).count
  end

  field :myReaction do |news_feed, options|
    next nil unless options[:current_user].present?

    reaction = news_feed.news_feed_reactions.find_by(user_id: options[:current_user].id)
    reaction&.useful
  end

  field :fineNewsSummary do |news_feed, options|
    next nil unless news_feed.fine_news_summary.present?

    locale = options[:locale]
    if locale.present? && %w{es pt}.include?(locale)
      news_feed.fine_news_summary_translations&.dig(locale).presence || news_feed.fine_news_summary
    else
      news_feed.fine_news_summary
    end
  end

  association :news_comments, blueprint: NewsCommentBlueprint
end
