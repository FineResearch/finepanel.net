# frozen_string_literal: true

require 'base64'

class WhatsappExportMailer < ApplicationMailer
  FROM = 'auto-export@fine-research.com'.freeze

  def export_ready_email(to:, file_path:)
    puts "[WhatsappExportMailer] export_ready_email start to=#{to} file_path=#{file_path}"
    Rails.logger.info("[WhatsappExportMailer] export_ready_email start to=#{to} file_path=#{file_path}")

    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    personalization = generate_personalization(to)
    personalization.subject = 'WhatsApp export ready'

    mail.add_personalization(personalization)

    mail.add_content(
      SendGrid::Content.new(
        type: 'text/plain',
        value: 'Your WhatsApp export is attached to this email.'
      )
    )

    if file_path.present? && File.exist?(file_path)
      attachment = SendGrid::Attachment.new
      attachment.content = Base64.strict_encode64(File.binread(file_path))
      attachment.type = 'text/csv'
      attachment.filename = File.basename(file_path)
      attachment.disposition = 'attachment'
      mail.add_attachment(attachment)
    end

    response = send_email(mail)

    puts "[WhatsappExportMailer] SendGrid status=#{response.status_code} body=#{response.body}"
    Rails.logger.info("[WhatsappExportMailer] SendGrid status=#{response.status_code} body=#{response.body}")

    response
  end

  def export_failed_email(to:, error_message:)
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    personalization = generate_personalization(to)
    personalization.subject = 'WhatsApp export failed'

    mail.add_personalization(personalization)

    mail.add_content(
      SendGrid::Content.new(
        type: 'text/plain',
        value: "The WhatsApp export failed.\n\nError: #{error_message}"
      )
    )

    send_email(mail)
  end
end
