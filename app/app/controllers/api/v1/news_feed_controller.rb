module Api
  module V1
    class NewsFeedController < ApiController
      before_action :check_basic_auth

      respond_to :json

      def index
        specialty = Specialty.find_by(slug: params.dig("specialty"))

        if specialty.present?
          render json: NewsFeedBlueprint.render(specialty.news_feeds.order("alert_created_at #{set_sort}")[0..2], {locale: params.dig("locale")}), status: :ok
        else
          render json: [], status: :ok
        end
      end

      private

      def set_sort
        return 'DESC' unless params.dig("sort").present?
        params.dig("sort") == 'new' ? 'DESC' : 'ASC'
      end

    end
  end
end
