module DynamedApi
  class CreateNews

    ARTICLE_PATH = '/medsapi-dynamed/v1/articles/'

    def initialize(article_id)
      @article_id = article_id
      @finepanel_article = set_article
    end

    def process
      return set_error unless @finepanel_article.present?
      data = DynamedApi::Client.new("#{ARTICLE_PATH}#{@article_id}").process

      extract_news(data['updates']) if data['updates']
    end

    private

    def set_error
      Rails.logger.warn("===> Specialty #{@article_id} doesn't  exist")
    end

    def extract_news(data)
      last_news = data[0]

      news = NewsFeed.new(text: last_news['text'], anchor: last_news['anchor'], alert_created_at: last_news['timestamp'], update_type: last_news['updateType'], update_priority: last_news['updatePriority'], specialty_id: @finepanel_article.specialty_id, article_id: @finepanel_article.id)

      if news.save
        Rails.logger.info("News created: #{news.text}")
      else
        Rails.logger.warn("#{news.errors}")
      end
    end

    def set_article
      return unless @article_id.present?
      Article.find_by(dynamed_id: @article_id)
    end

  end
end
