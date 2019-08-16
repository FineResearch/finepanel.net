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

  def survey_progress_status(code)
    return 'Iniciada' if code == ConfigurationReader.status_initiated_survey
  end

  def history_payment_concept(concept)
    concept.downcase == 'filtro' ? t('dashboard.payment_history.history_comment.filter') : concept
  end

  def user_password(email)
    User.automated_password(email)
  end

  def dynamed_enable?(user_data)
    return false unless user_data.present?
    user_data[:dynamed] == ConfigurationReader.status_dynamed_enabled
  end

  def privacy_policy_page_lang
    cookies[:locale] == 'es' ? ConfigurationReader.privacy_policy_url_es : ConfigurationReader.privacy_policy_url_pt
  end
end
