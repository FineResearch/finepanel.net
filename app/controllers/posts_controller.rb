# frozen_string_literal: true

class PostsController < ApplicationController
  respond_to :html, :json

  def new
    @post = current_user.posts.new
  end

  def create
    @post = current_user.posts.create(post_params)
    if @post.valid?
      delete_old_posts
      render partial: 'posts/post', locals: { post: @post }
    else
      render json: { error_msg: @post.errors&.first[1] }, status: :unprocessable_entity
    end
  end

  def download
    file_path = Post.find(params[:id]).media.current_path
    send_file file_path, x_sendfile: true
  end

  def delete
    @post = Post.find_by(id: params[:id])&.destroy
    
    redirect_to root_path
  end

  private
  def post_params
    user_info = current_user.info_for_post(cookies[:respid])
    
    params
      .require(:post)
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
