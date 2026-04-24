class WhatsappProjectPanelist < ApplicationRecord
  belongs_to :user, optional: true

  STATUSES = %w[
    not_sent
    sent_no_response
    postponed
    survey_started
    filtered_with_agent
    filtered_without_agent
    completed_with_agent
    completed_without_agent
    cancelled
  ].freeze

  CONFIRMIT_STATUSES = %w[
    filtered
    completed
  ].freeze

  validates :project_code, presence: true
  validates :panelist_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  before_validation :normalize_project_code

  scope :for_project, ->(project_code) { where(project_code: project_code.to_s) }
  scope :with_status, ->(status) { where(status: status) }

  def self.find_for_survey_click(path:, r:, s:)
    normalized_path = normalize_path(path)

    find_by(
      survey_path: normalized_path,
      survey_r: r.to_s,
      survey_s: s.to_s
    )
  end

  def self.find_for_cancel_click(path:, r:, s:)
    normalized_path = normalize_path(path)

    find_by(
      cancel_path: normalized_path,
      cancel_r: r.to_s,
      cancel_s: s.to_s
    ) || find_by(
      survey_path: normalized_path,
      survey_r: r.to_s,
      survey_s: s.to_s
    )
  end

  def self.normalize_path(path)
    value = path.to_s.strip
    return value if value.start_with?('/')

    "/#{value}"
  end

  def mark_sent!(attrs = {})
    update!(
      {
        status: 'sent_no_response',
        message_sent_at: Time.current
      }.merge(attrs)
    )
  end

  def mark_postponed!
    update!(
      status: 'postponed',
      message_sent_at: Time.current
    )
  end

  def mark_started!
    update!(
      status: 'survey_started',
      clicked_at: clicked_at.presence || Time.current
    )
  end

  def mark_cancelled!
    update!(
      status: 'cancelled',
      cancelled_at: cancelled_at.presence || Time.current
    )
  end

  def mark_reply_received!
    update!(
      reply_received_at: reply_received_at.presence || Time.current
    )
  end

  def mark_agent_intervened!
    update!(agent_intervened: true)
  end

  def mark_final_result!(result)
    normalized_result = result.to_s.downcase
    raise ArgumentError, "Invalid confirmit result: #{result}" unless CONFIRMIT_STATUSES.include?(normalized_result)

    final_status =
      case normalized_result
      when 'filtered'
        agent_intervened? ? 'filtered_with_agent' : 'filtered_without_agent'
      when 'completed'
        agent_intervened? ? 'completed_with_agent' : 'completed_without_agent'
      end

    update!(
      confirmit_status: normalized_result,
      status: final_status,
      final_outcome_at: Time.current
    )
  end

  private

  def normalize_project_code
    self.project_code = project_code.to_s.strip
  end
end
