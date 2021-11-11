# frozen_string_literal: true

class NewsParser

  def initialize(text)
    @text = text
  end

  def process
    text_parser = Nokogiri::HTML.parse(@text).xpath('//li')
    return unless text_parser.present?
    news_extractor(text_parser)
  end

  private

  def news_extractor(text_parser)
    text_parser.each do |news_container|
      step_1 = news_container.children[3]
      next unless step_1.present?

      step_2 = step_1.children[1]
      next unless step_2.present?

      step_3 = step_2.attributes
      next unless step_3.present?

      news_link = step_3['href'].value

      slug = news_link[/https:\/\/www.dynamed.com(.*?)#/, 1]
      article = Article.find_by_slug(slug)

      article.present? ? create_news(article) : log_article_error(slug)
    end
  end

  def create_news(article)
    return unless article.present?
    delete_old_news(article.specialty.slug)
    NewsCreatorWorker.perform_async(article.dynamed_id)
  end

  def log_article_error(slug)
    Rails.logger.warn("===> The article with slug #{slug} does not exist")
  end

  def delete_old_news(slug)
    specialty = Specialty.find_by_slug(slug)
    return unless specialty.present?
    return if specialty.news_feeds.count <= NewsFeed::MAXIMUM_NEWS_BY_SPECIALTY
    new_news = specialty.news_feeds.order(alert_created_at: :asc).last(NewsFeed::MAXIMUM_NEWS_BY_SPECIALTY)
    date = new_news.first.alert_created_at
    specialty.news_feeds.where("alert_created_at < ?", date).destroy_all
  end
end
