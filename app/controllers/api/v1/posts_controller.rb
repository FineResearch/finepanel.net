module Api
  module V1
    class PostsController < ApiController
      before_action :check_basic_auth

      respond_to :json

      def index
        posts = Post.by_created_at
        render json: PostsBlueprint.render(posts), status: :ok
      end

      def create
        post = @current_user.posts.create(post_params)

        if post.valid?
          delete_old_posts
          render json: PostsBlueprint.render(post), status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end
      end

      private

      def post_params
        user_info = user_params_info

        params
          .permit(:text, :kind, :media, :external_media_url)
          .merge(user_info: user_info)
      end

      def delete_old_posts
        return if Post.all.count <= Post::ENTRIES_LIMIT
        new_posts = Post.order(created_at: :asc).last(Post::ENTRIES_LIMIT)
        date = new_posts.first.created_at
        Post.where("created_at < ?", date).destroy_all
      end
    end
  end
end
