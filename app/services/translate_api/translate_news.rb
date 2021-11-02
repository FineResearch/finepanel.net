require "google/cloud/translate/v2"

module TranslateApi
  class TranslateNews

    AVAILABLE_LOCALS = %w{es pt}

    def initialize(id)
      @id = id
      @news = NewsFeed.find_by(id: id)
      @translate = Google::Cloud::Translate::V2.new
    end

    def process
      return log_news_error unless @news.present?
      translate_news
    end

    private

    def translate_news
      AVAILABLE_LOCALS.each do |locale|
        title = @translate.translate(@news.title, to: locale).try(:text)
        text  = @translate.translate(@news.text, to: locale).try(:text)
        @news.news_feed_translations.create(locale: locale, title: title, text: text)
      end
    end

    def log_news_error
      Rails.logger.warn("===> The news with id #{@id} was not found")
    end
  end
end
