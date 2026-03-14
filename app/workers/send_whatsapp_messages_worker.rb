# frozen_string_literal: true

require 'csv'
require 'securerandom'

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
    campaign_uuid = SecureRandom.uuid

    csv_content.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        user = nil

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
        main_surveylink = "#{row[:surveylink]}&wp=1"

        phone_number_id = resolve_phone_number_id(user.whatsapp_number)
        from_phone_number = resolve_from_phone_number(user.whatsapp_number)
        support_email = resolve_support_email(values, user.whatsapp_number)

        client.send_message(
          phone_number_id: phone_number_id,
          to_number: user.whatsapp_number,
          parameters: build_whatsapp_params(user, row, values, cancel_link),
          language: language,
          template: 'survey_template'
        )

        WhatsappOutbound.create!(
          user: user,
          whatsapp_number: user.whatsapp_number,
          panelist_email: row[:username],
          panelist_id: row[:panelistid],
          sample_number: row[:samplenumber],
          support_email: support_email,
          from_phone_number: from_phone_number,
          from_phone_number_id: phone_number_id,
          subject: values[:asunto],
          project_code: values[:codigodelproyecto],
          duration: values[:duracion],
          incentive: values[:moneda_valor],
          sent_by: values[:envia],
          survey_link: row[:surveylink],
          main_survey_link: main_surveylink,
          template_name: 'survey_template',
          language: language,
          status: 'sent',
          campaign_uuid: campaign_uuid
        )
      rescue StandardError => e
        Rails.logger.error("[SendWhatsappMessagesWorker] Error Sending Whatsapp message to #{user&.whatsapp_number}: #{e.class} - #{e.message}")

        if user
          WhatsappOutbound.create!(
            user: user,
            whatsapp_number: user.whatsapp_number,
            panelist_email: row[:username],
            panelist_id: row[:panelistid],
            sample_number: row[:samplenumber],
            support_email: resolve_support_email(values, user.whatsapp_number),
            from_phone_number: resolve_from_phone_number(user.whatsapp_number),
            from_phone_number_id: resolve_phone_number_id(user.whatsapp_number),
            subject: values[:asunto],
            project_code: values[:codigodelproyecto],
            duration: values[:duracion],
            incentive: values[:moneda_valor],
            sent_by: values[:envia],
            survey_link: row[:surveylink],
            main_survey_link: row[:surveylink].present? ? "#{row[:surveylink]}&wp=1" : nil,
            template_name: 'survey_template',
            language: resolve_language(values[:idioma]),
            status: 'failed',
            error_message: "#{e.class} - #{e.message}",
            campaign_uuid: campaign_uuid
          )
        end

        next
      end
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
      ENV['WHATSAPP_MX_NUMBER_ID'] || ENV['WHATSAPP_AR_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']
    when phone.start_with?('57')
      ENV['WHATSAPP_CO_NUMBER_ID'] || ENV['WHATSAPP_AR_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']
    else
      ENV['WHATSAPP_AR_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']
    end
  end

  def resolve_from_phone_number(phone)
    phone = phone.to_s.gsub(/\D/, '')

    case
    when phone.start_with?('55')
      ENV['WHATSAPP_BR_NUMBER'] || ENV['TWILIO_DEFAULT_NUMBER'] || 'whatsapp-br'
    when phone.start_with?('52')
      ENV['WHATSAPP_MX_NUMBER'] || ENV['WHATSAPP_AR_NUMBER'] || ENV['TWILIO_DEFAULT_NUMBER'] || 'whatsapp-default'
    when phone.start_with?('57')
      ENV['WHATSAPP_CO_NUMBER'] || ENV['WHATSAPP_AR_NUMBER'] || ENV['TWILIO_DEFAULT_NUMBER'] || 'whatsapp-default'
    else
      ENV['WHATSAPP_AR_NUMBER'] || ENV['TWILIO_DEFAULT_NUMBER'] || 'whatsapp-default'
    end
  end

  def resolve_support_email(values, phone)
    return values[:emailsoporte] if values[:emailsoporte].present?

    phone = phone.to_s.gsub(/\D/, '')

    if phone.start_with?('55')
      'suporte@finepanel.net'
    else
      'soporte@finepanel.net'
    end
  end

  def fetch_variables(text)
    email_information = {}
    pattern = /(IDIOMA|ASUNTO|CODIGO DEL PROYECTO|DURACION|MONEDA-VALOR|ENVIA|EMAIL SOPORTE|NUMERO SOPORTE): (.*?)\r\n/

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
