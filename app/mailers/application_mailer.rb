# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include SendGrid

  def initialize
    @client = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY']).client
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

  recipient_email.to_s.split(',').map(&:strip).reject(&:blank?).each do |email|
    personalization.add_to(Email.new(email: email))
  end

  personalization
end

def self.send_plain_email(to:, from:, subject:, text_body:)
  mail = SendGrid::Mail.new
  mail.from = Email.new(email: from)

  personalization = SendGrid::Personalization.new
  to.to_s.split(',').map(&:strip).reject(&:blank?).each do |email|
    personalization.add_to(Email.new(email: email))
  end
  personalization.subject = subject.to_s

  mail.add_personalization(personalization)
  mail.add_content(SendGrid::Content.new(type: 'text/plain', value: text_body.to_s))

  new.send_email(mail)
end

  def send_email(mail)
    response = @client.mail._('send').post(request_body: mail.to_json)

    Rails.logger.info("[SendGrid] status=#{response.status_code} body=#{response.body}\nheaders=#{response.headers}")

    response
  rescue StandardError => e
    Rails.logger.error("[SendGrid] error=#{e.class} message=#{e.message}")
    raise e
  end
end
