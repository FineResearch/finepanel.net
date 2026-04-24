class WhatsappMailer < ApplicationMailer
  TEMPLATE_IDS = {
    inbound_alert: 'd-fbf2f82614224f4d8595d51a0ea89b5f'
  }.freeze

  FROM = 'comentarios@finepanel.net'.freeze

  def inbound_message_alert(
    profile_name:,
    from_number:,
    user_id:,
    message_body:,
    message_id:,
    message_type:,
    timestamp: nil,
    phone_number_id: nil,
    display_phone_number: nil,
    panelist_country: nil,
    project_code: nil,
    sample_number: nil,
    support_email: nil,
    survey_subject: nil,
    duration: nil,
    incentive: nil,
    sent_by: nil,
    survey_link: nil,
    main_survey_link: nil,
    panelist_id: nil,
    from_phone_number: nil,
    from_phone_number_id: nil,
    include_respondent_phone: false,
    respondent_phone: nil,
    panelist_first_name: nil,
    panelist_last_name: nil,
    panelist_email: nil, # 👈 FIX
    **_extra             # 👈 FUTURE-PROOF
  )
    to_email = support_email.presence || default_recipient_for(from_number)

    mail = generate_email(TEMPLATE_IDS[:inbound_alert], FROM)
    personalization = generate_personalization(to_email)

    payload = {
      profile_name: profile_name,
      from_number: from_number,
      user_id: user_id,
      message_body: message_body,
      message_id: message_id,
      message_type: message_type,
      timestamp: timestamp,
      phone_number_id: phone_number_id,
      display_phone_number: display_phone_number,
      panelist_country: panelist_country,
      project_code: project_code,
      sample_number: sample_number,
      support_email: to_email,
      survey_subject: survey_subject,
      duration: duration,
      incentive: incentive,
      sent_by: sent_by,
      survey_link: survey_link,
      main_survey_link: main_survey_link,
      panelist_id: panelist_id,
      from_phone_number: from_phone_number,
      from_phone_number_id: from_phone_number_id,
      include_respondent_phone: include_respondent_phone,
      respondent_phone: respondent_phone,
      panelist_first_name: panelist_first_name,
      panelist_last_name: panelist_last_name,
      panelist_email: panelist_email # 👈 FIX
    }

    personalization.add_dynamic_template_data(
      subject: build_subject(payload),
      profile_name: profile_name,
      from_number: from_number,
      user_id: user_id,
      message_body: message_body,
      message_id: message_id,
      message_type: message_type,
      project_code: project_code,
      survey_subject: survey_subject,
      duration: duration,
      incentive: incentive,
      sent_by: sent_by,
      survey_link: survey_link,
      main_survey_link: main_survey_link,
      panelist_id: panelist_id,
      sample_number: sample_number,
      support_email: to_email,
      from_phone_number: from_phone_number,
      from_phone_number_id: from_phone_number_id,
      inbound_timestamp: timestamp,
      phone_number_id: phone_number_id,
      display_phone_number: display_phone_number,
      panelist_country: panelist_country,
      include_respondent_phone: include_respondent_phone,
      respondent_phone: respondent_phone,
      panelist_first_name: panelist_first_name,
      panelist_last_name: panelist_last_name,
      panelist_email: panelist_email # 👈 FIX
    )

    mail.add_personalization(personalization)
    send_email(mail)
  end

  def whatsapp_opt_out_alert(
    support_email:,
    exclusion_link:,
    from_number: nil,
    profile_name: nil,
    project_code: nil,
    panelist_id: nil,
    panelist_first_name: nil,
    panelist_last_name: nil,
    panelist_email: nil,
    panelist_country: nil
  )
    to_email = support_email.presence || default_recipient_for(from_number)

    template_id = ENV['SENDGRID_OPT_OUT_TEMPLATE_ID'].presence || 'd-76ee6fefea244ccebc49c82ed024c599'
    mail = generate_email(template_id, FROM)

    personalization = generate_personalization(to_email)

    personalization.subject = build_opt_out_subject(
      from_number: from_number,
      profile_name: profile_name,
      project_code: project_code,
      panelist_id: panelist_id
    )

    personalization.add_dynamic_template_data(
      panelist_name: profile_name,
      panelist_id: panelist_id,
      project_code: project_code,
      phone: from_number,
      timestamp: Time.current.iso8601,
      exclusion_link: exclusion_link,
      panelist_first_name: panelist_first_name,
      panelist_last_name: panelist_last_name,
      panelist_email: panelist_email,
      panelist_country: panelist_country
    )

    mail.add_personalization(personalization)
    send_email(mail)
  end

  private

  def default_recipient_for(phone)
    normalized_phone = normalize_phone(phone)

    if normalized_phone.start_with?('55')
      'suporte@finepanel.net'
    else
      'soporte@finepanel.net'
    end
  end

  def build_subject(payload)
    first_name = payload[:panelist_first_name].to_s.strip
    last_name = payload[:panelist_last_name].to_s.strip
    full_name = [first_name, last_name].reject(&:blank?).join(' ')
    full_name = payload[:profile_name].to_s.strip if full_name.blank?
    full_name = 'Panelista sin identificar' if full_name.blank?

    panelist = payload[:panelist_id].presence || payload[:user_id].presence
    project = payload[:project_code].presence

    subject = "Respuesta WAPP de: #{full_name}"
    subject += " (#{panelist})" if panelist.present?
    subject += " en #{project}" if project.present?
    subject
  end

  def build_opt_out_subject(from_number:, profile_name:, project_code:, panelist_id:)
    project = project_code.presence || 'N/A'
    panelist = panelist_id.presence || 'N/A'
    profile = profile_name.presence || 'N/A'
    number = from_number.presence || 'N/A'

    "Solicitud de exclusión WhatsApp - Proyecto: #{project} - Panelista: #{panelist} - Nombre: #{profile} - Número: #{number}"
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')
  end
end
