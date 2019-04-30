# frozen_string_literal: true

class SurveyLink < ApplicationRecord
  def valid_link?
    ConfirmitGateway.valid_survey_link?(link) && created_at >= Time.now - 60.days
  end
end
