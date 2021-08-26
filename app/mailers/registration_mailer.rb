class RegistrationMailer < ApplicationMailer
  TEMPLATE_IDS = {
    password_recovery: 'd-3ed4979a9677410a8341112f4ff94b0f'
  }

  FROM = "admin@finepanel.net"

  def password_recovery_email(recipient_email, password)
    mail = generate_email(TEMPLATE_IDS[:password_recovery], FROM)
    personalization = generate_personalization(recipient_email)

    personalization.add_dynamic_template_data({
      subject: I18n.t('mailers.registration.password_recovery.subject'),
      title: I18n.t('mailers.registration.password_recovery.title'),
      paragraph: I18n.t('mailers.registration.password_recovery.paragraph'),
      password_pre: I18n.t('mailers.registration.password_recovery.password_pre', password:  password),
      notice: I18n.t('mailers.registration.password_recovery.notice', link: 'www.finepanel.net')
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end
end
