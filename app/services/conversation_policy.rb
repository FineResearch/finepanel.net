class ConversationPolicy
  attr_reader :internal_user, :conversation

  ALLOWED_TEMPLATE_NAMES = %w[
    reminder_support_v1
    reminder_support_v1_es
    reopen_conversation_v1
  ].freeze

  def initialize(internal_user:, conversation:)
    @internal_user = internal_user
    @conversation = conversation
  end

  def can_access_conversation?
    return false if internal_user.blank?
    return false unless internal_user.active?
    return false if conversation.blank?

    internal_user.can_access_project?(conversation.project_code)
  end

  def can_view?
    can_access_conversation?
  end

  def can_resolve?
    can_access_conversation?
  end

  def can_reopen?
    can_access_conversation?
  end

  def can_send_free_text?
    return false unless can_access_conversation?

    conversation.within_customer_care_window?
  end

  def can_send_template?(template_name)
    return false unless can_access_conversation?

    normalized_template_name = template_name.to_s.strip
    return false if normalized_template_name.blank?

    ALLOWED_TEMPLATE_NAMES.include?(normalized_template_name)
  end

  def free_text_blocked_reason
    return 'user_not_allowed' unless can_access_conversation?
    return nil if can_send_free_text?

    'outside_24h_window'
  end

  def template_blocked_reason(template_name)
    return 'user_not_allowed' unless can_access_conversation?

    normalized_template_name = template_name.to_s.strip
    return 'blank_template_name' if normalized_template_name.blank?
    return 'invalid_template' unless ALLOWED_TEMPLATE_NAMES.include?(normalized_template_name)

    nil
  end

  def allowed_actions
    {
      view: can_view?,
      resolve: can_resolve?,
      reopen: can_reopen?,
      send_free_text: can_send_free_text?,
      send_template: can_access_conversation?,
      allowed_templates: allowed_template_names_for_conversation
    }
  end

  def conversation_window_status
    return 'unavailable' if conversation.blank?
    return 'open' if conversation.within_customer_care_window?

    'closed'
  end

  def allowed_template_names_for_conversation
    return [] unless can_access_conversation?

    ALLOWED_TEMPLATE_NAMES
  end
end
