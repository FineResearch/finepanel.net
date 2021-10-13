module Api
  module V1
    class CommentsController < ApiController
      before_action :set_user_data

      def create
        user_info = @current_user.info_for_post(nil, params['email'])
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
