# Payload publico y minimo para el carrusel del Home (sin login): solo
# titulo, especialidad y fuente, nunca el contenido completo de la
# evidencia.
class HomeHighlightBlueprint < Blueprinter::Base
  identifier :id

  field :specialtySlug do |_news_feed, options|
    options[:specialty_slug]
  end

  field :specialtyName do |news_feed|
    news_feed.specialty.name
  end

  field :title do |news_feed, options|
    locale = options[:locale]
    translated_title =
      if locale.present? && %w{es pt}.include?(locale)
        news_feed.fine_news_summary_translations&.dig(locale, 'editorial_content', 'title')
      end

    translated_title.presence || news_feed.fine_news_summary.dig('editorial_content', 'title')
  end

  field :evidenceSource do |news_feed|
    news_feed.fine_news_summary.dig('article_metadata', 'evidence_source')
  end
end
