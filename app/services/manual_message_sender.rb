class ManualMessageSender
  Result = Struct.new(
    :success?,
    :message,
    :error_code,
    :whatsapp_message,
    :provider_response,
    keyword_init: true
  )

  DEFAULT_TEMPLATE_LANGUAGE = 'es_MX'.freeze

  attr_reader :internal_user, :conversation

  def initialize(internal_user:, conversation:)
    @internal_user = internal_user
    @conversation = conversation
  end

  def send_reminder!
    policy = ConversationPolicy.new(
      internal_user: internal_user,
      conversation: conversation
    )

    panelist_phone = extract_panelist_phone
    return error_result('missing_panelist_phone', 'Could not determine panelist phone number') unless panelist_phone.present?

    language = resolve_language(panelist_phone, nil)

    if policy.can_send_free_text?
      send_free_text!(body: default_free_text(conversation, language))
    else
      template_name = reminder_template_for_language(language)

      send_template!(
        template_name: template_name,
        template_language: language,
        parameters: default_reminder_template_parameters(conversation)
      )
    end
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

    language = resolve_language(panelist_phone, template_language)

    begin
      provider_response = whats_app_client.send_message(
        phone_number_id: phone_number_id,
        to_number: panelist_phone,
        template: normalized_template_name,
        language: language,
        parameters: normalized_template_parameters(parameters)
      )

      whatsapp_message = conversation.whatsapp_messages.create!(
        direction: 'outbound',
        source: 'template',
        internal_user: internal_user,
        message_body: nil,
        template_name: normalized_template_name,
        template_language: language
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

  def default_reminder_template_parameters(conversation)
    [
      default_greeting_title(conversation),
      default_greeting_name(conversation)
    ]
  end

  def reminder_template_for_language(language)
    language == 'pt_BR' ? 'reminder_support_v1' : 'reminder_support_v1_es'
  end

  def default_free_text(conversation, language)
    greeting = full_greeting(conversation)

    if language == 'pt_BR'
      "Olá #{greeting}, gostaríamos de saber se precisa de ajuda para participar do estudo. Estamos por aqui para ajudar no que precisar."
    else
      "Hola #{greeting}, queríamos ver si necesita ayuda para participar del estudio. Por cualquier duda estamos por aquí para ayudarle."
    end
  end

  def full_greeting(conversation)
    title = default_greeting_title(conversation)
    name = default_greeting_name(conversation)

    "#{title} #{name}".strip
  end

  def default_greeting_title(conversation)
    user = conversation.respond_to?(:user) ? conversation.user : nil
    title = user&.professional_title.to_s.strip

    return title if title.present?

    'Dr(a).'
  end

  def default_greeting_name(conversation)
    user = conversation.respond_to?(:user) ? conversation.user : nil

    name =
      user&.first_name.presence ||
      user&.last_name.presence ||
      'Doctor/a'

    name.to_s.strip
  end

  def error_result(code, message)
    Result.new(
      success?: false,
      error_code: code,
      message: message
    )
  end

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

  def resolve_language(phone, requested_language)
    normalized_phone = normalize_phone(phone)

    return 'pt_BR' if normalized_phone.start_with?('55')
    return requested_language.to_s.strip if requested_language.present?

    'es_MX'
  end

  def resolve_phone_number_id(phone)
    normalized_phone = normalize_phone(phone)

    default_id = ENV['WHATSAPP_US_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']

    case
    when normalized_phone.start_with?('55')
      ENV['WHATSAPP_BR_NUMBER_ID'] || default_id
    when normalized_phone.start_with?('52')
      ENV['WHATSAPP_MX_NUMBER_ID'] || default_id
    when normalized_phone.start_with?('57')
      ENV['WHATSAPP_CO_NUMBER_ID'] || default_id
    when normalized_phone.start_with?('54')
      ENV['WHATSAPP_AR_NUMBER_ID'] || default_id
    else
      default_id
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
