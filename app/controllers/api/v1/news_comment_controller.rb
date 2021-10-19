module Api
  module V1
    class NewsCommentController < ApiController
      before_action :check_basic_auth

      def create
        parent_news = NewsFeed.find(params['parent_newsfeed_id'])

        comment = current_user.news_comments.create(text: params['text'], user_info: user_params_info, news_feed_id: params[:parent_newsfeed_id].to_i)

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
    end
  end
end
