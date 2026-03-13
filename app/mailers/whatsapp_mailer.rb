class WhatsappMailer < ApplicationMailer
  TEMPLATE_IDS = {
    inbound_alert: 'd-fbf2f82614224f4d8595d51a0ea89b5f'
  }

FROM = "comentarios@finepanel.net"
  TO = "dcasar@fine-research.com"

  def inbound_message_alert(payload)
    mail = generate_email(TEMPLATE_IDS[:inbound_alert], FROM)
    personalization = generate_personalization(TO)

    personalization.add_dynamic_template_data({
      subject: "[WhatsApp Inbound] #{payload[:project_code]} - #{payload[:from_number]}",
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
      main_survey_link: payload[:main_survey_link]
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end
end

 
