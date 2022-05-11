module Api
  module V1
    class NewsFeedController < ApiController
      before_action :check_basic_auth

      respond_to :json

      def index
        specialty = Specialty.find_by(slug: params.dig("specialty"))

        if specialty.present?
          render json: NewsFeedBlueprint.render(specialty.news_feeds.order(set_sort), {locale: params.dig("locale")}), status: :ok
        else
          render json: [], status: :ok
        end
      end

      def search
        if params.dig("query").present?
          news = NewsFeed.search_by_text(params.dig("query")).or(NewsFeed.search_by_title(params.dig("query"))).distinct
          render json: NewsFeedBlueprint.render(news.order(set_sort), {locale: params.dig("locale")}), status: :ok
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

      def set_sort
        return "alert_created_at DESC" unless params.dig("sort").present?

        case params.dig("sort")
        when "new"
          "alert_created_at DESC"
        when "old"
          "alert_created_at ASC"
        when "views"
          "view_count DESC"
        else
          "alert_created_at DESC"
        end
      end

      def news_attributes
        article_slug = params[:link].present? ? params[:link][/#{'https://www.dynamed.com'}(.*?)#{'#'}/m, 1] : nil
        article      = Article.find_by_slug(article_slug)
        specialty    = Specialty.find_by_slug(params[:specialty])
        anchor       = params[:link].present? ? params[:link][/^[^#]*#([\s\S]*)$/m, 1] : ''
        alert_date   = Date.parse(params[:date]) rescue nil

        return {} unless article.try(:specialty_id) == specialty.try(:id)

        attributes = {
          text: params[:text],
          anchor: anchor,
          alert_created_at: alert_date,
          update_type: params[:category],
          update_priority: 'standard',
          specialty_id: specialty.id,
          article_id: article.id
        }
      end
    end
  end
end
