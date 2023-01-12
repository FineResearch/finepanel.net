# frozen_string_literal: true

require 'csv'

class SendWhatsappMessagesWorker
  include Sidekiq::Worker
  include FilesHelper

  def perform(file_path, text)
    Rails.logger.info(
      "Starting SendWhatsappMessagesWorker, feed_file_path: #{file_path}"
    )

    csv_content = tab_separated_to_hash(file_path)
    twilio = ::Twilio::Client.new
    values = fetch_variables(text)

    csv_content.each do |row|
      next if row[:respid].nil?

      user = User.find_by_hash_respid(row[:respid])

      next unless user

      Rails.logger.info("Sending Whatsapp message to #{user.whatsapp_number}")
      message = I18n.t(
        'whatsapp.message',
        title: user.professional_title,
        name: user.first_name,
        last_name: user.last_name,
        survey_link: row[:surveylink],
        subject: values[:asunto],
        project_code: values[:codigodelproyecto],
        duration: values[:duracion],
        currency: values[:moneda_valor],
        sender_name: values[:envia],
        locale: values[:idioma]
      )

      twilio.send_message(
        to_number: user.whatsapp_number,
        message: message
      )
    rescue StandardError => e
      Rails.logger.error("[SendWhatsappMessagesWorker] Error Sending Whatsapp message to #{user.whatsapp_number}: #{e.message[0, 200]}")
      next
    end

    File.delete(file_path)

    Rails.logger.info('Finished SendWhatsappMessagesWorker')
  rescue StandardError => e
    Rails.logger.error { "SendWhatsappMessagesWorker error: #{e.message[0, 200]} (#{e.class}" }
  end

  private

  def fetch_variables(text)
    text.split("\n").map do |item|
      item.gsub(/\r/,"").split(":")
    end.to_h
       .transform_keys { |key| key.to_s.downcase.gsub('-', '_').gsub(/\s+/, "") }
       .transform_keys(&:to_sym)
       .transform_values(&:lstrip)
  end
end
