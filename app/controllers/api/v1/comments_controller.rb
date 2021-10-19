module Api
  module V1
    class CommentsController < ApiController
      before_action :check_basic_auth

      def create
        user_info = user_params_info
        parent_post = Post.find(params['parent_post_id'])

        comment = current_user.comments.create(text: params['text'], user_info: user_info, post: parent_post)

        if comment.valid?
          render json: CommentBlueprint.render(comment), status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end

      end

      def destroy
        comment = Comment.find_by(id: params[:id])

        if comment&.destroy
          render json: {message: 'Delete Comment Success'}, status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end
      end

    end
  end
end
