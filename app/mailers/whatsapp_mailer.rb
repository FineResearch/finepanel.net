class WhatsappMailer < ApplicationMailer
  TEMPLATE_IDS = {
    inbound_alert: 'd-fbf2f82614224f4d8595d51a0ea89b5f'
  }

  FROM = "comentarios@finepanel.net"

  def inbound_message_alert(payload)
    to_email = payload[:support_email].presence || default_recipient_for(payload[:from_number])

    mail = generate_email(TEMPLATE_IDS[:inbound_alert], FROM)
    personalization = generate_personalization(to_email)

    personalization.add_dynamic_template_data({
      subject: build_subject(payload),
      profile_name: payload[:profile_name],
      from_number: payload[:from_number],
      user_id: payload[:user_id],
      message_body: payload[:message_body],
      message_id: payload[:message_id],
      message_type: payload[:message_type],
      project_code: payload[:project_code],
      survey_subject: payload[:survey_subject],
      duration: payload[:duration],
      incentive: payload[:incentive],
      sent_by: payload[:sent_by],
      survey_link: payload[:survey_link],
      main_survey_link: payload[:main_survey_link],
      panelist_id: payload[:panelist_id],
      sample_number: payload[:sample_number],
      support_email: to_email,
      from_phone_number: payload[:from_phone_number],
      from_phone_number_id: payload[:from_phone_number_id],
      inbound_timestamp: payload[:inbound_timestamp]
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  private

  def default_recipient_for(phone)
    normalized_phone = phone.to_s.gsub(/\D/, '')

    if normalized_phone.start_with?('55')
      'suporte@finepanel.net'
    else
      'soporte@finepanel.net'
    end
  end

  def build_subject(payload)
    parts = ['[WhatsApp Inbound]']
    parts << payload[:project_code] if payload[:project_code].present?
    parts << payload[:sample_number] if payload[:sample_number].present?
    parts << payload[:from_number] if payload[:from_number].present?
    parts.join(' - ')

def build_subject(payload)
   project = payload[:project_code] || 'N/A'
   panelist = payload[:panelist_id] || 'N/A'
   sample = payload[:sample_number] || 'N/A'

   "Mensaje de Whatsapp - Proyecto: #{project} - Panelista: #{panelist} - samplenumber: #{sample}"
  end
  
end

