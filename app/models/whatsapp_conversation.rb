class WhatsappConversation < ApplicationRecord
  belongs_to :user, optional: true

  belongs_to :resolved_by_user,
             class_name: 'InternalUser',
             optional: true,
             inverse_of: :resolved_whatsapp_conversations

  has_many :whatsapp_messages, dependent: :destroy

  validates :panelist_id, presence: true
  validates :project_code, presence: true
  validates :status, presence: true

  before_validation :normalize_project_code

  scope :open_conversations, -> { where(status: 'open') }
  scope :recent_first, -> { order(last_message_at: :desc, updated_at: :desc) }
  scope :unread, -> { where(has_unread_messages: true) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :open_threads, -> { where(resolved_at: nil) }
  scope :for_project, ->(project_code) { where(project_code: project_code.to_s) }

  def within_customer_care_window?
    window_expires_at.present? && window_expires_at > Time.current
  end

  def customer_care_window_open?
    within_customer_care_window?
  end

  def status
    return 'resolved' if resolved_at.present?

    super.presence || 'open'
  end

  def touch_inbound!
    now = Time.current
    update!(
      last_inbound_at: now,
      last_message_at: now,
      has_unread_messages: true,
      window_expires_at: now + 24.hours,
      resolved_at: nil,
      resolved_by_user_id: nil
    )
  end

  def touch_outbound!
    now = Time.current
    update!(
      last_outbound_at: now,
      last_message_at: now,
      has_unread_messages: false
    )
  end

  def mark_resolved!(internal_user)
    update!(
      resolved_at: Time.current,
      resolved_by_user_id: internal_user&.id,
      has_unread_messages: false
    )
  end

  def reopen!
    update!(
      resolved_at: nil,
      resolved_by_user_id: nil,
      last_message_at: Time.current
    )
  end

  def related_outbounds
    return WhatsappOutbound.none unless defined?(WhatsappOutbound)

    scope = WhatsappOutbound.all
    filters_applied = false
    column_names = WhatsappOutbound.column_names

    if column_names.include?('panelist_id') && panelist_id.present?
      scope = scope.where(panelist_id: panelist_id)
      filters_applied = true
    elsif column_names.include?('user_id') && user_id.present?
      scope = scope.where(user_id: user_id)
      filters_applied = true
    end

    if column_names.include?('project_code') && project_code.present?
      scope = scope.where(project_code: project_code)
      filters_applied = true
    end

    return WhatsappOutbound.none unless filters_applied

    scope
  end

  private

  def normalize_project_code
    self.project_code = project_code.to_s.strip
  end
end
