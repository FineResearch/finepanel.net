# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include SendGrid

  def initialize
    @client = SendGrid::API.new(api_key: ENV["SENDGRID_API_KEY"]).client
  end

  private

  def generate_email(template_id, from)
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: from)
    mail.template_id = template_id

    mail
  end

  def generate_personalization(recipient_email)
    personalization = SendGrid::Personalization.new
    personalization.add_to(Email.new(email: recipient_email))

    personalization
  end

  def send_email(mail)
    @client.mail._('send').post(request_body: mail.to_json)
  end
end
