module Api
  module V1
    class NewsCommentController < ApiController
      before_action :set_user_data

      def create
        parent_news = NewsFeed.find(params['parent_newsfeed_id'])

        comment = current_user.news_comments.create(text: params['text'], user_info: set_user_info, news_feed_id: params[:parent_newsfeed_id].to_i)

        if comment.valid?
          render json: NewsCommentBlueprint.render(comment), status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end

      end

      def destroy
        comment = NewsComment.find_by(id: params[:id])

        if comment&.destroy
          render json: {message: 'Delete Comment Success'}, status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end
      end

      private

      def set_user_info
        return {} unless params[:text].present?
        {email: params[:email], complete_name: params[:complete_name] , country: params[:country], city: params[:city], specialty: params[:specialty]}
      end

    end
  end
end
