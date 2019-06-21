# frozen_string_literal: true

class CommentsController < ApplicationController
  def create
    user_info = current_user.info_for_post(cookies[:respid])
    parent_post = Post.find(params[:comment][:parent_post_id])
    @comment = current_user.comments.create(text: params[:comment][:text], user_info: user_info, post: parent_post)
    if @comment.valid?
      render partial: 'posts/comment', locals: { comment: @comment }
    else
      render body: nil, status: :unprocessable_entity
    end
  end
end
