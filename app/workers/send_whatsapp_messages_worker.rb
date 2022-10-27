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
    text_parser = TextParser.new(text)

    csv_content.each do |row|
      next if row[:respid].nil?

      user = User.find_by_hash_respid(row[:respid])

      next unless user

      Rails.logger.info("Sending Whatsapp message to #{user.whatsapp_number}")

      # The following variables should be named as they come in the message
      tituloest = user.formal_title
      titulo = user.professional_title
      name = user.first_name
      apellido = user.last_name
      surveylink = row[:surveylink]
      message = text_parser.bind_values(binding)

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
end
