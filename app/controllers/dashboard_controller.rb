# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @survey_list = ConfirmitGateway.get_surveys_for_user(current_user)
  end
end
