require "google/cloud/translate/v2"

module TranslateApi
  class TranslateFineNewsSummary
    AVAILABLE_LOCALS = %w{es pt}

    EDITORIAL_FIELDS = %w{
      title reading_cta what_this_evidence_shows what_is_new
      clinical_implications limitations_and_precautions
    }

    def initialize(id)
      @id = id
      @news = NewsFeed.find_by(id: id)
    end

    def process
      return unless @news.present? && @news.fine_news_summary.present?

      translations = {}

      AVAILABLE_LOCALS.each do |locale|
        translated = translate_summary(locale)
        translations[locale] = translated if translated.present?
      end

      @news.update_column(:fine_news_summary_translations, translations) if translations.present?
    end

    private

    # Si Google Translate no esta disponible (por ejemplo, sin credenciales
    # en desarrollo local), esto no falla el worker: simplemente no se guarda
    # traduccion para ese idioma y la app muestra el contenido original.
    def translate_summary(locale)
      summary  = @news.fine_news_summary
      metadata = summary["article_metadata"] || {}
      editorial = summary["editorial_content"] || {}
      community = summary["community_discussion"] || {}

      {
        "article_metadata" => {
          "article_category" => translate_text(metadata["article_category"], locale),
          "evidence_source" => metadata["evidence_source"],
          "suggested_image" => metadata["suggested_image"]
        },
        "editorial_content" => EDITORIAL_FIELDS.each_with_object({}) do |field, hash|
          hash[field] = translate_text(editorial[field], locale)
        end,
        "community_discussion" => {
          "question" => translate_text(community["question"], locale)
        }
      }
    rescue StandardError => e
      Rails.logger.warn("[TranslateFineNewsSummary] locale=#{locale} news_id=#{@id} error=#{e.class}: #{e.message}")
      nil
    end

    def translate_text(text, locale)
      return nil if text.blank?

      translate_client.translate(text, to: locale).try(:text)
    end

    def translate_client
      @translate_client ||= Google::Cloud::Translate::V2.new
    end
  end
end
