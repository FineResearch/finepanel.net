class ConversationContextBuilder
  def initialize(conversation:)
    @conversation = conversation
  end

  def as_json
    outbound = primary_outbound

    {
      project_code: @conversation.project_code,
      panelist_id: @conversation.panelist_id,
      conversation_status: @conversation.status,
      conversation_window_status: conversation_window_status,
      whatsapp_number: outbound_value(outbound, :whatsapp_number, :from_phone_number, :phone, :phone_number),
      template_name: outbound_value(outbound, :template_name),
      template_language: outbound_value(outbound, :template_language, :language),
      outbound_sent_at: outbound&.created_at&.iso8601,
      survey_subject: outbound_value(outbound, :survey_subject, :study_title, :project_name, :survey_name),
      duration: outbound_value(outbound, :duration),
      incentive: outbound_value(outbound, :incentive),
      sent_by: outbound_value(outbound, :sent_by),
      survey_link: outbound_value(outbound, :survey_link),
      main_survey_link: outbound_value(outbound, :main_survey_link),
      sample_number: outbound_value(outbound, :sample_number),
      panelist_country: outbound_value(outbound, :panelist_country),
      panelist_first_name: outbound_value(outbound, :panelist_first_name),
      panelist_last_name: outbound_value(outbound, :panelist_last_name),
      user_id: outbound_value(outbound, :user_id),
      outbound_id: outbound&.id
    }.delete_if { |_key, value| value.blank? }
  end

  private

  def primary_outbound
    @primary_outbound ||= begin
      scope = @conversation.related_outbounds
      scope = scope.order(created_at: :asc) if scope.respond_to?(:order)
      scope.first
    end
  end

  def conversation_window_status
    @conversation.within_customer_care_window? ? 'open' : 'closed'
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
