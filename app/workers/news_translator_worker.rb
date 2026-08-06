class NewsTranslatorWorker
  include Sidekiq::Worker

  def perform(news_id)
    safely_translate { TranslateApi::TranslateNews.new(news_id).process }
    safely_translate { TranslateApi::TranslateFineNewsSummary.new(news_id).process }

    Rails.logger.info("Finished NewsTranslatorWorker => news_id: #{news_id}")
  end

  private

  # Si Google Translate no esta disponible (ej: sin credenciales en local),
  # cada paso falla de forma independiente sin tumbar el resto del job.
  def safely_translate
    yield
  rescue StandardError => e
    Rails.logger.warn("[NewsTranslatorWorker] #{e.class}: #{e.message}")
  end
end
