class NewsTranslatorWorker
  include Sidekiq::Worker

  def perform(news_id)
    TranslateApi::TranslateNews.new(news_id).process

    logger.info("Finished NewsTranslatorWorker => news_id: #{news_id}")
  end
end
