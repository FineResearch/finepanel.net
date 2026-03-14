# frozen_string_literal: true

require 'csv'

class SendWhatsappMessagesWorker
  include Sidekiq::Worker
  include FilesHelper

  BATCH_SIZE = 500

  def perform(file_path, text)
    Rails.logger.info(
      "Starting SendWhatsappMessagesWorker, feed_file_path: #{file_path}"
    )

    csv_content = tab_separated_to_hash(file_path)
    client = WhatsApp::Client.new
    values = fetch_variables(text)
    user = nil

    csv_content.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        Rails.logger.info("[SendWhatsappMessagesWorker] row=#{row.to_h.inspect}")

        if row[:username].nil?
          Rails.logger.info("[SendWhatsappMessagesWorker] skipping row because username is nil")
          next
        end

        user = User.find_from_email(row[:username])

        unless user
          Rails.logger.info("[SendWhatsappMessagesWorker] no user found for username=#{row[:username]}")
          next
        end

        Rails.logger.info("Sending Whatsapp message to #{user.whatsapp_number}")

        language = resolve_language(values[:idioma])
        cancel_link = "#{row[:surveylink]}&exit=cancelar"

        phone_number_id = resolve_phone_number_id(user.whatsapp_number)

        client.send_message(
          phone_number_id: phone_number_id,
          to_number: user.whatsapp_number,
          parameters: build_whatsapp_params(user, row, values, cancel_link),
          language: language,
          template: 'survey_template'
        )

        main_surveylink = "#{row[:surveylink]}&wp=1"

        WhatsappOutbound.create!(
          user: user,
          whatsapp_number: user.whatsapp_number,
          panelist_email: row[:username],
          subject: values[:asunto],
          project_code: values[:codigodelproyecto],
          duration: values[:duracion],
          incentive: values[:moneda_valor],
          sent_by: values[:envia],
          survey_link: row[:surveylink],
          main_survey_link: main_surveylink,
          template_name: 'survey_template',
          language: language,
          status: 'sent'
        )
      end
    rescue StandardError => e
      Rails.logger.error("[SendWhatsappMessagesWorker] Error Sending Whatsapp message to #{user&.whatsapp_number}: #{e.class} - #{e.message}")
      next
    end

    File.delete(file_path) if File.exist?(file_path)

    Rails.logger.info('Finished SendWhatsappMessagesWorker')
  rescue StandardError => e
    Rails.logger.error("[SendWhatsappMessagesWorker] fatal error: #{e.class} - #{e.message}")
  end

  private

  def resolve_phone_number_id(phone)

    phone = phone.to_s.gsub(/\D/, '')

    case
    when phone.start_with?('55')
      ENV['WHATSAPP_BR_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']

    when phone.start_with?('52')
      ENV['WHATSAPP_MX_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']

    when phone.start_with?('57')
      ENV['WHATSAPP_CO_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']

    else
      ENV['WHATSAPP_AR_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']
    end

  end

  def fetch_variables(text)
    email_information = {}
    pattern = /(IDIOMA|ASUNTO|CODIGO DEL PROYECTO|DURACION|MONEDA-VALOR|ENVIA|NUMERO SOPORTE): (.*?)\r\n/

    text.scan(pattern) do |key, value|
      symbolized_key = key.downcase.gsub('-', '_').gsub(/\s+/, "").to_sym
      email_information[symbolized_key] = value.try(:strip)
    end

    email_information
  end

  def build_whatsapp_params(user, row, values, cancel_link)

    main_surveylink = "#{row[:surveylink]}&wp=1"

    text_values = [
      user.professional_title,
      user.first_name,
      user.last_name,
      values[:asunto],
      values[:codigodelproyecto],
      values[:duracion],
      values[:moneda_valor],
      main_surveylink,
      values[:envia],
      cancel_link
    ]

    text_values.map do |text|
      { type: 'text', text: text }
    end

  end

  def resolve_language(language)
    language.include?('por') || language.include?('pt') ? 'pt_BR' : language
  end
end
