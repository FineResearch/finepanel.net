class ManualMessageSender
  Result = Struct.new(
    :success?,
    :message,
    :error_code,
    :whatsapp_message,
    :provider_response,
    keyword_init: true
  )

  DEFAULT_TEMPLATE_LANGUAGE = 'es'.freeze

  attr_reader :internal_user, :conversation

  def initialize(internal_user:, conversation:)
    @internal_user = internal_user
    @conversation = conversation
  end

  def send_free_text!(body:)
    policy = ConversationPolicy.new(
      internal_user: internal_user,
      conversation: conversation
    )

    unless policy.can_send_free_text?
      return Result.new(
        success?: false,
        error_code: policy.free_text_blocked_reason,
        message: 'Free text message not allowed for this conversation'
      )
    end

    message_body = body.to_s.strip
    if message_body.blank?
      return Result.new(
        success?: false,
        error_code: 'blank_body',
        message: 'Message body cannot be blank'
      )
    end

    panelist_phone = extract_panelist_phone
    unless panelist_phone.present?
      return Result.new(
        success?: false,
        error_code: 'missing_panelist_phone',
        message: 'Could not determine panelist phone number'
      )
    end

    phone_number_id = resolve_phone_number_id(panelist_phone)
    if phone_number_id.blank?
      return Result.new(
        success?: false,
        error_code: 'missing_phone_number_id',
        message: 'Could not determine WhatsApp sender phone_number_id for this panelist'
      )
    end

    begin
      provider_response = whats_app_client.send_text_message(
        phone_number_id: phone_number_id,
        to_number: panelist_phone,
        body: message_body
      )

      whatsapp_message = conversation.whatsapp_messages.create!(
        direction: 'outbound',
        source: 'agent',
        internal_user: internal_user,
        message_body: message_body
      )

      conversation.touch_outbound!

      Result.new(
        success?: true,
        message: 'Message sent successfully',
        whatsapp_message: whatsapp_message,
        provider_response: provider_response
      )
    rescue => e
      Result.new(
        success?: false,
        error_code: 'send_failed',
        message: e.message
      )
    end
  end

  def send_template!(template_name:, template_language: DEFAULT_TEMPLATE_LANGUAGE, parameters: [])
    normalized_template_name = template_name.to_s.strip
    normalized_language = template_language.to_s.strip.presence || DEFAULT_TEMPLATE_LANGUAGE

    if normalized_template_name.blank?
      return Result.new(
        success?: false,
        error_code: 'blank_template_name',
        message: 'Template name cannot be blank'
      )
    end

    policy = ConversationPolicy.new(
      internal_user: internal_user,
      conversation: conversation
    )

    unless policy.can_send_template?(normalized_template_name)
      return Result.new(
        success?: false,
        error_code: policy.template_blocked_reason(normalized_template_name),
        message: 'Template message not allowed for this conversation'
      )
    end

    panelist_phone = extract_panelist_phone
    unless panelist_phone.present?
      return Result.new(
        success?: false,
        error_code: 'missing_panelist_phone',
        message: 'Could not determine panelist phone number'
      )
    end

    phone_number_id = resolve_phone_number_id(panelist_phone)
    if phone_number_id.blank?
      return Result.new(
        success?: false,
        error_code: 'missing_phone_number_id',
        message: 'Could not determine WhatsApp sender phone_number_id for this panelist'
      )
    end

    begin
      provider_response = whats_app_client.send_message(
        phone_number_id: phone_number_id,
        to_number: panelist_phone,
        template: normalized_template_name,
        language: normalized_language,
        parameters: normalized_template_parameters(parameters)
      )

      whatsapp_message = conversation.whatsapp_messages.create!(
        direction: 'outbound',
        source: 'template',
        internal_user: internal_user,
        message_body: nil,
        template_name: normalized_template_name,
        template_language: normalized_language
      )

      conversation.touch_outbound!

      Result.new(
        success?: true,
        message: 'Template sent successfully',
        whatsapp_message: whatsapp_message,
        provider_response: provider_response
      )
    rescue => e
      Result.new(
        success?: false,
        error_code: 'send_failed',
        message: e.message
      )
    end
  end

  private

  def whats_app_client
    @whats_app_client ||= WhatsApp::Client.new
  end

  def extract_panelist_phone
    if conversation.respond_to?(:panelist_phone) && conversation.panelist_phone.present?
      return conversation.panelist_phone
    end

    latest_outbound = WhatsappOutbound.where(
      panelist_id: conversation.panelist_id,
      project_code: conversation.project_code
    ).order(created_at: :desc).first

    return nil unless latest_outbound.present?
    return latest_outbound.whatsapp_number if latest_outbound.respond_to?(:whatsapp_number) && latest_outbound.whatsapp_number.present?

    nil
  end

  def resolve_phone_number_id(phone)
    normalized_phone = normalize_phone(phone)

    case
    when normalized_phone.start_with?('55')
      ENV['WHATSAPP_BR_NUMBER_ID']
    when normalized_phone.start_with?('52')
      ENV['WHATSAPP_MX_NUMBER_ID']
    when normalized_phone.start_with?('57')
      ENV['WHATSAPP_CO_NUMBER_ID']
    when normalized_phone.start_with?('54')
      ENV['WHATSAPP_AR_NUMBER_ID']
    else
      ENV['WHATSAPP_US_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']
    end
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')
  end

  def normalized_template_parameters(parameters)
    return [] if parameters.blank?

    parameters.map do |value|
      if value.is_a?(Hash)
        value
      else
        {
          type: 'text',
          text: value.to_s
        }
      end
    end
  end
end
