module Api
  module V1
    class NewsFeedController < ApiController
      before_action :check_basic_auth, except: [:home_highlights]

      respond_to :json

      # Especialidades destacadas en el carrusel del Home publico, en el
      # orden en que deben rotar. Se usan los mismos slugs que ya expone
      # utils/specialtySlug.js del lado del frontend.
      HOME_HIGHLIGHT_SPECIALTIES = %w[
        oncology
        hematology
        cardiology
        pediatrics
        rheumatology
        dermatology
        neurology
        endocrinology
        gastroenterology
      ].freeze

      # Endpoint publico (sin autenticacion, el Home se ve sin login): para
      # cada especialidad destacada, devuelve solo la ultima actualizacion
      # con fine_news_summary (si la ultima de esa especialidad todavia no
      # tiene el formato nuevo, se salta esa especialidad en esta rotacion,
      # sin buscar mas atras en el tiempo).
      def home_highlights
        highlights = HOME_HIGHLIGHT_SPECIALTIES.map do |slug|
          specialty = Specialty.find_by(slug: slug)
          next unless specialty.present?

          news_feed = specialty.news_feeds
            .order(alert_created_at: :desc, created_at: :desc)
            .first
          next unless news_feed.present? && news_feed.fine_news_summary.present?

          HomeHighlightBlueprint.render_as_hash(
            news_feed,
            locale: params.dig("locale"),
            specialty_slug: slug,
          )
        end.compact

        render json: highlights, status: :ok
      end

      def index
        specialty = Specialty.find_by(slug: params.dig("specialty"))

        if specialty.present?
          news_feeds = specialty.news_feeds.includes(:news_comments).order(set_sort)
          annotate_comment_reactions(news_feeds)
          render json: NewsFeedBlueprint.render(news_feeds, {locale: params.dig("locale"), current_user: current_user}), status: :ok
        else
          render json: [], status: :ok
        end
      end

      def search
        if params.dig("query").present?
          news = NewsFeed.search_by_text(params.dig("query")).or(NewsFeed.search_by_title(params.dig("query"))).distinct
          news_feeds = news.includes(:news_comments).order(set_sort)
          annotate_comment_reactions(news_feeds)
          render json: NewsFeedBlueprint.render(news_feeds, {locale: params.dig("locale"), current_user: current_user}), status: :ok
        else
          render json: [], status: :ok
        end
      end

      def increment_view_count
        news_feed = NewsFeed.find(params[:id])

        news_feed.view_count += 1
        news_feed.save!

        render json: news_feed.view_count, status: :ok

        rescue ActiveRecord::RecordNotFound
          render json: {}, status: :not_found
        rescue ActiveRecord::RecordInvalid
          render json: {}, status: :unprocessable_entity
      end

      # Registra si al usuario le resulto util la noticia (pulgar arriba/abajo).
      # Un solo voto por usuario y noticia: si vuelve a marcar la misma opcion
      # que ya tenia, se interpreta como que quiere quitar su voto.
      def react
        news_feed = NewsFeed.find(params[:id])
        useful = ActiveModel::Type::Boolean.new.cast(params[:useful])
        reaction = NewsFeedReaction.find_or_initialize_by(user: current_user, news_feed: news_feed)

        if reaction.persisted? && reaction.useful == useful
          reaction.destroy!
          my_reaction = nil
        else
          reaction.useful = useful
          reaction.save!
          my_reaction = reaction.useful
        end

        render json: {
          myReaction: my_reaction,
          usefulCount: news_feed.news_feed_reactions.where(useful: true).count,
        }, status: :ok

        rescue ActiveRecord::RecordNotFound
          render json: {}, status: :not_found
        rescue ActiveRecord::RecordInvalid
          render json: {}, status: :unprocessable_entity
      end

      def create
        news = NewsFeed.new(news_attributes)

        if news.save
          NewsTranslatorWorker.perform_async(news.id)
          render json: news, status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end
      end

      def destroy
        news = NewsFeed.find(params[:id])

        news.destroy

        render json: news, status: :ok

        rescue ActiveRecord::RecordNotFound
          render json: {}, status: :not_found
        rescue ActiveRecord::RecordInvalid
          render json: {}, status: :unprocessable_entity
      end

      private

      # Setea reaction_count/my_comment_reaction (atributos transitorios,
      # ver NewsComment) en cada comentario de la pagina ANTES de
      # renderizar, con 2 queries agregadas para toda la pagina en vez de
      # una por comentario (evita N+1 -- ver NewsCommentBlueprint). No
      # depende de que Blueprinter propague options a un blueprint anidado
      # (association :news_comments dentro de NewsFeedBlueprint), que no
      # esta garantizado -- los datos ya viajan seteados en el objeto.
      def annotate_comment_reactions(news_feeds)
        comments = news_feeds.flat_map(&:news_comments)
        return if comments.empty?

        comment_ids = comments.map(&:id)
        counts = NewsCommentReaction.where(news_comment_id: comment_ids).group(:news_comment_id).count
        my_reacted_ids = current_user.present? ?
          NewsCommentReaction.where(news_comment_id: comment_ids, user_id: current_user.id).pluck(:news_comment_id).to_set :
          Set.new

        comments.each do |comment|
          comment.reaction_count = counts[comment.id] || 0
          comment.my_comment_reaction = my_reacted_ids.include?(comment.id)
        end
      end

      def set_sort
        return "alert_created_at DESC, created_at DESC" unless params.dig("sort").present?

        case params.dig("sort")
        when "new"
          "alert_created_at DESC, created_at DESC"
        when "old"
          "alert_created_at ASC, created_at ASC"
        when "views"
          "view_count DESC"
        else
          "alert_created_at DESC, created_at DESC"
        end
      end

      def news_attributes
        article_slug = params[:link].present? ? params[:link][/#{'https://www.dynamed.com'}(.*?)#{'#'}/m, 1] : nil
        specialty    = Specialty.find_by_slug(params[:specialty])
        fine_news_summary = parsed_fine_news_summary

        article = Article.find_by_slug(article_slug)
        article ||= build_article_from_summary(article_slug, specialty, fine_news_summary)

        return {} unless specialty.present? && article.present?

        anchor       = params[:link].present? ? params[:link][/^[^#]*#([\s\S]*)$/m, 1] : ''
        alert_date   = Date.parse(params[:date]) rescue nil
        update_type  = params[:link].present? ? params[:link][/#{'https://www.dynamed.com/'}(.*?)#{'/'}/m, 1] : ''

        attributes = {
          text: text_for(fine_news_summary),
          anchor: anchor,
          alert_created_at: alert_date,
          update_type: update_type,
          update_priority: 'standard',
          specialty_id: specialty.id,
          article_id: article.id
        }

        attributes[:fine_news_summary] = fine_news_summary if fine_news_summary.present?

        attributes
      end

      # Cuando viene un fine_news_summary para un articulo que DynaMed
      # todavia no sincronizo localmente, lo creamos a partir del propio
      # resumen en lugar de exigir que ya exista (la sincronizacion con
      # DynaMed no es el unico camino para publicar una noticia curada).
      def build_article_from_summary(article_slug, specialty, fine_news_summary)
        return nil unless article_slug.present? && specialty.present? && fine_news_summary.present?

        title = fine_news_summary.dig('editorial_content', 'title')
        return nil unless title.present?

        dynamed_id = article_slug.split('/').last

        Article.find_or_create_by(dynamed_id: dynamed_id) do |article|
          article.slug = article_slug
          article.title = title
          article.specialty = specialty
        end
      end

      # El campo "Noticia" del formulario es opcional cuando viene un
      # fine_news_summary: el texto de respaldo (usado para presence/uniqueness)
      # se toma del titulo editorial en ese caso.
      def text_for(fine_news_summary)
        return params[:text] if params[:text].present?
        return nil unless fine_news_summary.present?

        fine_news_summary.dig('editorial_content', 'title')
      end

      def parsed_fine_news_summary
        return nil unless params[:fine_news_summary].present?

        JSON.parse(params[:fine_news_summary])
      rescue JSON::ParserError
        nil
      end
    end
  end
end
