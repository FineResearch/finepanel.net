# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :set_user_data, only: [:index, :payment_info, :participations]

  def index
    @posts = Post.by_created_at.paginate(page: params[:page], total_entries: Post::ENTRIES_LIMIT)
    @participations = []
    @survey_list = []
  end

  def participations
    @participations = ConfirmitGateway.get_participations_for_user(@user_data)
    respond_to do |format|
      format.js
    end
  end

  def survey_list
    @survey_list = ConfirmitGateway.get_surveys_for_user(current_user, cookies[:respid])
    respond_to do |format|
      format.js
    end
  end

  def payment_info
    @payment_info = ConfirmitGateway.get_payments_for_user(@user_data)
    respond_to do |format|
      format.js
    end
  end

  def payment_history
    history = Payment.get_payment_history_for_user(cookies[:respid])
    payments_sum = history.map{|payment| payment.credit }.sum()
    pending_credit = params[:pending_credit].to_i
    if payments_sum.present?
      payment_row = payments_sum > pending_credit
      credit_row = payments_sum < pending_credit
    end

    render partial: 'dashboard/payment_history_table', locals: { history: history, payments_sum: payments_sum, pending_credit: pending_credit, payment_row: payment_row, credit_row: credit_row}
  end

  private

  def set_user_data
    @user_data = current_user.profile_data(cookies[:respid])
  end
end
