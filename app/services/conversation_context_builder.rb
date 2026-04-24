class ConversationContextBuilder
  def initialize(conversation:)
    @conversation = conversation
  end

  def as_json
    outbound = primary_outbound
    user = panelist_user
    inbound = last_inbound_message

    {
      project_code: @conversation.project_code,
      panelist_id: @conversation.panelist_id,
      panelist_first_name: panelist_first_name(outbound, user),
      panelist_last_name: panelist_last_name(outbound, user),
      panelist_country: panelist_country(outbound, user),
      panelist_email: panelist_email(outbound, user),
      conversation_status: @conversation.status,
      conversation_window_status: conversation_window_status,
      requires_human_follow_up: requires_human_follow_up?(inbound),
      last_inbound_reply_type: last_inbound_reply_type(inbound),
      last_inbound_requires_reply: requires_human_follow_up?(inbound),
      last_inbound_within_24h: last_inbound_within_24h?(inbound),
      whatsapp_number: outbound_value(outbound, :whatsapp_number, :from_phone_number, :phone, :phone_number),
      template_name: outbound_value(outbound, :template_name),
      template_language: outbound_value(outbound, :template_language, :language),
      outbound_sent_at: outbound&.created_at&.iso8601,
      survey_subject: outbound_value(outbound, :survey_subject, :subject, :study_title, :project_name, :survey_name),
      duration: outbound_value(outbound, :duration),
      incentive: outbound_value(outbound, :incentive),
      sent_by: outbound_value(outbound, :sent_by),
      survey_link: outbound_value(outbound, :survey_link),
      main_survey_link: outbound_value(outbound, :main_survey_link),
      sample_number: outbound_value(outbound, :sample_number),
      user_id: outbound_value(outbound, :user_id),
      outbound_id: outbound&.id
    }.delete_if { |key, value| value.blank? && ![:requires_human_follow_up, :last_inbound_requires_reply, :last_inbound_within_24h].include?(key) }
  end

  private

  def primary_outbound
    @primary_outbound ||= begin
      scope = @conversation.related_outbounds
      scope = scope.order(created_at: :asc) if scope.respond_to?(:order)
      scope.first
    end
  end

  def panelist_user
    return @panelist_user if defined?(@panelist_user)

    @panelist_user =
      if @conversation.respond_to?(:user) && @conversation.user.present?
        @conversation.user
      elsif @conversation.panelist_id.present?
        User.find_by(id: @conversation.panelist_id)
      end
  end

  def project_panelist
    return @project_panelist if defined?(@project_panelist)

    @project_panelist = WhatsappProjectPanelist.find_by(
      project_code: @conversation.project_code,
      panelist_id: @conversation.panelist_id
    )
  end

  def panelist_first_name(outbound, user)
    outbound_value(outbound, :panelist_first_name, :first_name) ||
      user_value(user, :first_name)
  end

  def panelist_last_name(outbound, user)
    outbound_value(outbound, :panelist_last_name, :last_name) ||
      user_value(user, :last_name)
  end

  def panelist_country(outbound, user)
    outbound_value(outbound, :panelist_country, :country) ||
      user_value(user, :country) ||
      project_panelist_value(:country)
  end

  def panelist_email(outbound, user)
    outbound_value(outbound, :panelist_email, :email) ||
      user_value(user, :email) ||
      project_panelist_value(:panelist_email)
  end

  def project_panelist_value(field_name)
    record = project_panelist
    return nil if record.blank?
    return nil unless record.respond_to?(field_name)

    value = record.public_send(field_name)
    value if value.present?
  end

  def user_value(user, field_name)
    return nil if user.blank?
    return nil unless user.respond_to?(field_name)

    value = user.public_send(field_name)
    value if value.present?
  end

  def conversation_window_status
    @conversation.within_customer_care_window? ? 'open' : 'closed'
  end

  def requires_human_follow_up?(inbound = nil)
    return false if @conversation.blank?
    return false if @conversation.status.to_s == 'resolved'
    return false unless @conversation.respond_to?(:has_unread_messages)
    return false unless @conversation.has_unread_messages

    inbound ||= last_inbound_message
    return false if inbound.blank?

    text = message_text(inbound)
    return false if text.blank?
    return false if ['1', '2'].include?(text)

    true
  end

  def last_inbound_reply_type(inbound = nil)
    inbound ||= last_inbound_message
    return 'none' if inbound.blank?

    text = message_text(inbound, preserve_blank: true)
    return 'blank' if text.blank?
    return 'one' if text == '1'
    return 'two' if text == '2'

    'other'
  end

  def last_inbound_within_24h?(inbound = nil)
    inbound ||= last_inbound_message
    return nil if inbound.blank?
    return nil unless inbound.respond_to?(:created_at)
    return false if inbound.created_at.blank?

    inbound.created_at >= 24.hours.ago
  end

  def last_inbound_message
    return nil unless @conversation.respond_to?(:messages) || @conversation.respond_to?(:whatsapp_messages)

    scope =
      if @conversation.respond_to?(:whatsapp_messages)
        @conversation.whatsapp_messages
      else
        @conversation.messages
      end

    return nil unless scope.respond_to?(:where)

    scope.where(direction: 'inbound').order(created_at: :desc).first
  end

  def message_text(message, preserve_blank: false)
    return nil if message.blank?

    [:message_body, :body, :text, :message_text, :content].each do |field_name|
      next unless message.respond_to?(field_name)

      raw_value = message.public_send(field_name)
      value = raw_value.to_s.strip.downcase
      return value if value.present?
      return '' if preserve_blank && !raw_value.nil?
    end

    preserve_blank ? '' : nil
  end

  def outbound_value(outbound, *candidate_fields)
    return nil if outbound.blank?

    candidate_fields.each do |field_name|
      field_key = field_name.to_s

      if outbound.respond_to?(:has_attribute?) && outbound.has_attribute?(field_key)
        value = outbound[field_key]
        return value if value.present?
      end

      next unless outbound.respond_to?(field_name)

      value = outbound.public_send(field_name)
      return value if value.present?
    end

    nil
  end
end
