# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    user_data = current_user.profile_data(cookies[:respid])
    @survey_list = ConfirmitGateway.get_surveys_for_user(current_user, cookies[:respid])
    @payment_info = ConfirmitGateway.get_payments_for_user(user_data)
    @currency = ConfirmitGateway.get_currency_for_user(user_data)
    @participations = ConfirmitGateway.get_participations_for_user(user_data)
    @posts = Post.all.order(created_at: :desc).paginate(page: params[:page], total_entries: Post::ENTRIES_LIMIT)
  end
end
