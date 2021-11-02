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
          news = NewsFeed.joins(:article).search_by_text(params.dig("query")).or(NewsFeed.search_by_title(params.dig("query")))
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

    end
  end
end
