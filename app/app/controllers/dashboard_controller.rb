# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    user_data = current_user.profile_data(session[:respid])
    @survey_list = ConfirmitGateway.get_surveys_for_user(current_user, session[:respid])
    @payment_info = ConfirmitGateway.get_payments_for_user(user_data)
    @currency = ConfirmitGateway.get_currency_for_user(user_data)
    @participations = ConfirmitGateway.get_participations_for_user(user_data)
  end
end
