# frozen_string_literal: true

module DashboardHelper
  def survey_status(code)
    case code
    when 1
      t ('dashboard.survey_status.complete_to_pay')
    when 2 || 3
      t ('dashboard.survey_status.attempt_to_pay')
    when 8
      t ('dashboard.survey_status.complete_paid')
    when 9
      t ('dashboard.survey_status.attempt_paid')
    when 88
      t ('dashboard.survey_status.complete_donated')
    when 98
      t ('dashboard.survey_status.attempt_donated')
    when 85 || 95
      t ('dashboard.survey_status.not_paid_for_duplicity')
    end
  end
end
