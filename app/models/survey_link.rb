# frozen_string_literal: true

class SurveyLink < ApplicationRecord

   # -- Scopes --
  scope :active, -> { where(closed: false) }

  def valid_link?
    ConfirmitGateway.valid_survey_link?(link) && created_at >= Time.now - 60.days
  end

  def data_from_valid_survey(language_param)
    ConfirmitGateway.data_from_valid_survey(link, language_param, id)
  end
end
