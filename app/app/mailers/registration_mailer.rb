class RegistrationMailer < ActionMailer::Base
  default from: "admin@finepanel.net <admin@finepanel.net>"

  def password_recovery_email(email, password)
    @password = password
    mail(:to => email, :subject => I18n.t('mailers.registration.password_recovery.subject'))
  end
end
