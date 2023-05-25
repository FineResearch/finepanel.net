# frozen_string_literal: true

require 'csv'

class SendWhatsappMessagesWorker
  include Sidekiq::Worker
  include FilesHelper

  BATCH_SIZE = 500
  DEFAULT_SUPPORT_NUMBER = ENV['WHATSAPP_SUPPORT_NUMBER'] || '+5491130321213' # Diego Casavarilla number

  def perform(file_path, text)
    Rails.logger.info(
      "Starting SendWhatsappMessagesWorker, feed_file_path: #{file_path}"
    )

    csv_content = tab_separated_to_hash(file_path)
    #twilio = ::Twilio::Client.new
    client = WhatsApp::Client.new
    values = fetch_variables(text)
    support_link = "https://api.whatsapp.com/send?phone=#{values[:numerosoporte] || DEFAULT_SUPPORT_NUMBER}"

    csv_content.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        next if row[:username].nil?

        user = User.find_from_email(row[:username])
        next unless user

        Rails.logger.info("Sending Whatsapp message to #{user.whatsapp_number}")

        client.send_message(to_number: user.whatsapp_number,
                            parameters: build_whatsapp_params(user, row, values, support_link),
                            language: resolve_language(values[:idioma]),
                            template: 'survey_template')
      end
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

  def build_whatsapp_params(user, row, values, support_link)
    # we have to respect the order of the params, based on Whatsapp template
    text_values = [
      user.professional_title,
      user.first_name,
      user.last_name,
      values[:asunto],
      values[:codigodelproyecto],
      values[:duracion],
      values[:moneda_valor],
      row[:surveylink],
      support_link,
      values[:envia],
      "#{row[:surveylink]}",
      "#{row[:surveylink]}",
    ]

    text_values.map do |text|
      { type: 'text', text: text }
    end
  end

  def resolve_language(language)
    language.include?('por') || language.include?('pt') ? 'pt_BR' : language
  end
end
