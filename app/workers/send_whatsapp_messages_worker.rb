# frozen_string_literal: true

require 'csv'
require 'securerandom'
require 'uri'
require 'cgi'

class SendWhatsappMessagesWorker
  include Sidekiq::Worker
  include FilesHelper

  BATCH_SIZE = 500
  TEMPLATE_NAME = 'survey_template'.freeze

  def perform(file_path, text)
    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Starting worker, feed_file_path=#{file_path}"
    )

    Rails.logger.info("[SendWhatsappMessagesWorker] raw_text=#{text.inspect}")

    csv_content = tab_separated_to_hash(file_path)
values = fetch_variables(text)
include_respondent_phone = values.key?(:agregartel)

Rails.logger.info("[SendWhatsappMessagesWorker] parsed_values=#{values.inspect}")
Rails.logger.info("[SendWhatsappMessagesWorker] include_respondent_phone=#{include_respondent_phone}")
    if csv_content.blank?
      Rails.logger.warn(
        "[SendWhatsappMessagesWorker] Aborting because file has no rows file_path=#{file_path}"
      )
      return
    end

    project_code = values[:codigodelproyecto].to_s.strip
    sample_number = extract_single_sample_number!(csv_content)

    client = WhatsApp::Client.new
    campaign_uuid = SecureRandom.uuid

    csv_content.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        
	process_row(row, values, include_respondent_phone, campaign_uuid, client)
      rescue StandardError => e
        Rails.logger.error(
          "[SendWhatsappMessagesWorker] Unexpected row-level error row=#{safe_row_log(row)} error=#{e.class} - #{e.message}"
        )
        next
      end
    end

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Finished worker campaign_uuid=#{campaign_uuid} project_code=#{project_code} sample_number=#{sample_number}"
    )
  rescue StandardError => e
    Rails.logger.error(
      "[SendWhatsappMessagesWorker] Fatal error: #{e.class} - #{e.message}"
    )
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
  ensure
    cleanup_file(file_path)
  end

  private

   def process_row(row, values, include_respondent_phone, campaign_uuid, client)
    Rails.logger.info("[SendWhatsappMessagesWorker] row=#{safe_row_log(row)}")

    username = row[:username].to_s.strip
    return if username.blank?

    user = User.find_from_email(username)
    return unless user

    whatsapp_number = normalize_phone(user.whatsapp_number)
    return if whatsapp_number.blank?

    language = resolve_language(whatsapp_number)

    original_survey_link = row[:surveylink].to_s.strip
    return if original_survey_link.blank?

    original_cancel_link = build_cancel_link(original_survey_link).to_s.strip

    tracked_survey_link = WhatsApp::TrackedLinkBuilder
      .tracked_link(original_survey_link)
      .to_s
      .strip

    tracked_cancel_link = WhatsApp::TrackedLinkBuilder
      .tracked_link(original_cancel_link)
      .to_s
      .strip

    phone_number_id = resolve_phone_number_id(whatsapp_number)
    from_phone_number = resolve_from_phone_number(whatsapp_number)
    support_email = resolve_support_email(values, whatsapp_number)

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] original_survey_link=#{original_survey_link.inspect} " \
      "original_cancel_link=#{original_cancel_link.inspect} " \
      "tracked_survey_link=#{tracked_survey_link.inspect} " \
      "tracked_cancel_link=#{tracked_cancel_link.inspect} " \
      "values=#{values.inspect}"
    )

    validate_tracking_links!(
      original_survey_link: original_survey_link,
      original_cancel_link: original_cancel_link,
      tracked_survey_link: tracked_survey_link,
      tracked_cancel_link: tracked_cancel_link
    )

    upsert_whatsapp_project_panelist!(
      user: user,
      row: row,
      values: values,
      whatsapp_number: whatsapp_number,
      support_email: support_email,
      original_survey_link: original_survey_link,
      original_cancel_link: original_cancel_link,
      tracked_survey_link: tracked_survey_link,
      tracked_cancel_link: tracked_cancel_link
    )

    template_param_values = build_template_param_values(
      user: user,
      values: values,
      tracked_survey_link: tracked_survey_link,
      tracked_cancel_link: tracked_cancel_link
    )

    log_template_param_values(template_param_values)
    validate_template_param_values!(template_param_values)

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Sending WhatsApp message to #{whatsapp_number} language=#{language} template=#{TEMPLATE_NAME}"
    )

    client.send_message(
      phone_number_id: phone_number_id,
      to_number: whatsapp_number,
      parameters: build_whatsapp_params(template_param_values),
      language: language,
      template: TEMPLATE_NAME
    )

    WhatsappOutbound.create!(
      user: user,
      whatsapp_number: whatsapp_number,
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
      survey_link: original_survey_link,
      main_survey_link: tracked_survey_link,
      template_name: TEMPLATE_NAME,
      language: language,
      status: 'sent',
      campaign_uuid: campaign_uuid,
      include_respondent_phone: include_respondent_phone
    )

    WhatsappDeliveryResult.create!(
      project_code: values[:codigodelproyecto],
      sample_number: row[:samplenumber],
      panelist_id: row[:panelistid],
      panelist_email: row[:username],
      whatsapp_number: whatsapp_number,
      status: 'sent'
    )
  rescue WhatsApp::InvalidNumberError => e
    handle_invalid_whatsapp(
      user: user,
      row: row,
      values: values,
      campaign_uuid: campaign_uuid,
      include_respondent_phone: include_respondent_phone,
      whatsapp_number: whatsapp_number,
      language: language,
      phone_number_id: phone_number_id,
      from_phone_number: from_phone_number,
      support_email: support_email,
      main_surveylink: tracked_survey_link,
      error: e
    )
  rescue WhatsApp::ApiError => e
    handle_failed_whatsapp(
      user: user,
      row: row,
      values: values,
      campaign_uuid: campaign_uuid,
      include_respondent_phone: include_respondent_phone,
      whatsapp_number: whatsapp_number,
      language: language,
      phone_number_id: phone_number_id,
      from_phone_number: from_phone_number,
      support_email: support_email,
      main_surveylink: tracked_survey_link,
      error: e
    )
  rescue StandardError => e
    handle_failed_whatsapp(
      user: user,
      row: row,
      values: values,
      campaign_uuid: campaign_uuid,
      include_respondent_phone: include_respondent_phone,      
      whatsapp_number: whatsapp_number,
      language: language,
      phone_number_id: phone_number_id,
      from_phone_number: from_phone_number,
      support_email: support_email,
      main_surveylink: tracked_survey_link,
      error: e
    )
  end

  def upsert_whatsapp_project_panelist!(
    user:,
    row:,
    values:,
    whatsapp_number:,
    support_email:,
    original_survey_link:,
    original_cancel_link:,
    tracked_survey_link:,
    tracked_cancel_link:
  )
    survey_parts = WhatsApp::TrackedLinkBuilder.extract_parts(original_survey_link)
    cancel_parts = WhatsApp::TrackedLinkBuilder.extract_parts(original_cancel_link)

    panelist = WhatsappProjectPanelist.find_or_initialize_by(
      project_code: values[:codigodelproyecto],
      panelist_id: row[:panelistid]
    )

    panelist.update!(
      user_id: user&.id,
      panelist_email: row[:username],
      sample_number: row[:samplenumber],
      whatsapp_number: whatsapp_number,
      country: phone_country(whatsapp_number),
      support_email: support_email,
      original_survey_link: original_survey_link,
      original_cancel_link: original_cancel_link,
      tracked_survey_link: tracked_survey_link,
      tracked_cancel_link: tracked_cancel_link,
      survey_path: survey_parts[:path],
      survey_r: survey_parts[:r],
      survey_s: survey_parts[:s],
      cancel_path: cancel_parts[:path],
      cancel_r: cancel_parts[:r],
      cancel_s: cancel_parts[:s],
      status: 'sent_no_response',
      message_sent_at: Time.current
    )
  end

  def build_template_param_values(user:, values:, tracked_survey_link:, tracked_cancel_link:)
    {
      professional_title: user&.professional_title.to_s.strip,
      last_name: user&.last_name.to_s.strip,
      asunto: values[:asunto].to_s.strip,
      duracion: values[:duracion].to_s.strip,
      moneda_valor: values[:moneda_valor].to_s.strip,
      tracked_survey_link: tracked_survey_link.to_s.strip,
      envia: values[:envia].to_s.strip,
      codigodelproyecto: values[:codigodelproyecto].to_s.strip,
      tracked_cancel_link: tracked_cancel_link.to_s.strip
    }
  end

  def log_template_param_values(template_param_values)
    template_param_values.each_with_index do |(key, value), idx|
      Rails.logger.info(
        "[SendWhatsappMessagesWorker] template_param_#{idx + 1} " \
        "key=#{key} value=#{value.inspect} blank=#{value.blank?}"
      )
    end
  end

  def validate_template_param_values!(template_param_values)
    blank_params = template_param_values.select { |_key, value| value.blank? }
    return if blank_params.empty?

    raise ArgumentError, "Blank WhatsApp template params: #{blank_params.keys.join(', ')}"
  end

  def build_whatsapp_params(template_param_values)
    template_param_values.values.map do |text|
      { type: 'text', text: text }
    end
  end

  def validate_tracking_links!(
    original_survey_link:,
    original_cancel_link:,
    tracked_survey_link:,
    tracked_cancel_link:
  )
    blank_links = {}
    blank_links[:original_survey_link] = original_survey_link if original_survey_link.blank?
    blank_links[:original_cancel_link] = original_cancel_link if original_cancel_link.blank?
    blank_links[:tracked_survey_link] = tracked_survey_link if tracked_survey_link.blank?
    blank_links[:tracked_cancel_link] = tracked_cancel_link if tracked_cancel_link.blank?

    return if blank_links.empty?

    raise ArgumentError, "Blank tracking links: #{blank_links.keys.join(', ')}"
  end

  def build_cancel_link(original_link)
    uri = URI.parse(original_link)
    params = CGI.parse(uri.query.to_s)
    params['exit'] = ['cancelar']
    uri.query = URI.encode_www_form(flatten_params(params))
    uri.to_s
  rescue URI::InvalidURIError => e
    raise ArgumentError,
          "Invalid original survey link for cancel link generation: #{original_link.inspect} - #{e.message}"
  end

  def phone_country(phone)
    normalized = normalize_phone(phone)

    case
    when normalized.start_with?('55')
      'Brasil'
    when normalized.start_with?('52')
      'México'
    when normalized.start_with?('57')
      'Colombia'
    when normalized.start_with?('54')
      'Argentina'
    else
      'Otro'
    end
  end

  def flatten_params(params)
    params.each_with_object([]) do |(key, values), array|
      Array(values).each do |value|
        array << [key, value]
      end
    end
  end

  def handle_invalid_whatsapp(
    user:,
    row:,
    values:,
    include_respondent_phone:,  
    campaign_uuid:,
    whatsapp_number:,
    language:,
    phone_number_id:,
    from_phone_number:,
    support_email:,
    main_surveylink:,
    error:
  )
    return if user.blank? || whatsapp_number.blank?

    error_message = "#{error.class} - #{error.message}"

    Rails.logger.warn(
      "[SendWhatsappMessagesWorker] Invalid WhatsApp user_id=#{user.id} whatsapp_number=#{whatsapp_number} error=#{error_message}"
    )

    WhatsappOutbound.create!(
      user: user,
      whatsapp_number: whatsapp_number,
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
      template_name: TEMPLATE_NAME,
      language: language,
      status: 'invalid_whatsapp',
      error_message: error_message,
      campaign_uuid: campaign_uuid,
      include_respondent_phone: include_respondent_phone
    )

    WhatsappDeliveryResult.create!(
      project_code: values[:codigodelproyecto],
      sample_number: row[:samplenumber],
      panelist_id: row[:panelistid],
      panelist_email: row[:username],
      whatsapp_number: whatsapp_number,
      status: 'invalid_whatsapp',
      error_message: error_message
    )

    register_invalid_whatsapp!(
      panelist_id: row[:panelistid],
      panelist_email: row[:username],
      whatsapp_number: whatsapp_number,
      project_code: values[:codigodelproyecto],
      error_message: error_message
    )
  end

  def handle_failed_whatsapp(
    user:,
    row:,
    values:,
    campaign_uuid:,
    include_respondent_phone:,
    whatsapp_number:,
    language:,
    phone_number_id:,
    from_phone_number:,
    support_email:,
    main_surveylink:,
    error:
  )
    return if user.blank? || whatsapp_number.blank?

    error_message = "#{error.class} - #{error.message}"

    Rails.logger.error(
      "[SendWhatsappMessagesWorker] Failed WhatsApp user_id=#{user.id} whatsapp_number=#{whatsapp_number} error=#{error_message}"
    )

    WhatsappOutbound.create!(
      user: user,
      whatsapp_number: whatsapp_number,
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
      template_name: TEMPLATE_NAME,
      language: language,
      status: 'failed',
      error_message: error_message,
      include_respondent_phone: include_respondent_phone,
      campaign_uuid: campaign_uuid
    )
  end

  def resolve_phone_number_id(phone)
    phone = normalize_phone(phone)

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
    phone = normalize_phone(phone)

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

    phone = normalize_phone(phone)

    if phone.start_with?('55')
      'suporte@finepanel.net'
    else
      'soporte@finepanel.net'
    end
  end

  def resolve_language(phone)
    phone = normalize_phone(phone)
    phone.start_with?('55') ? 'pt_BR' : 'es'
  end

  def register_invalid_whatsapp!(panelist_id:, panelist_email:, whatsapp_number:, project_code:, error_message:)
    normalized_number = normalize_phone(whatsapp_number)

    record = InvalidWhatsappNumber.find_by(whatsapp_number: normalized_number)

    if record
      record.update!(
        panelist_id: record.panelist_id.presence || panelist_id,
        panelist_email: panelist_email,
        last_detected_project_code: project_code,
        last_detected_at: Time.current,
        times_detected: record.times_detected.to_i + 1,
        last_error_message: error_message,
        active: true
      )
    else
      InvalidWhatsappNumber.create!(
        panelist_id: panelist_id,
        panelist_email: panelist_email,
        whatsapp_number: normalized_number,
        first_detected_project_code: project_code,
        last_detected_project_code: project_code,
        first_detected_at: Time.current,
        last_detected_at: Time.current,
        times_detected: 1,
        last_error_message: error_message,
        active: true
      )
    end
  end

  def fetch_variables(text)
    email_information = {}
    pattern = /^\s*(ASUNTO|CODIGO DEL PROYECTO|DURACION|MONEDA-VALOR|ENVIA|AGREGAR TEL|EMAIL SOPORTE)\s*:\s*(.*?)\s*$/i
    text.to_s.each_line do |line|
      normalized_line = line.to_s.encode(
        'UTF-8',
        invalid: :replace,
        undef: :replace,
        replace: ''
      ).strip

      match = normalized_line.match(pattern)
      next unless match

      key = match[1].to_s.upcase
      value = match[2].to_s.strip
      symbolized_key = key.downcase.gsub('-', '_').gsub(/\s+/, '').to_sym
      email_information[symbolized_key] = value
    end

    email_information
  end

  def extract_single_sample_number!(csv_content)
    sample_numbers = csv_content.map { |row| row[:samplenumber].to_s.strip }
                                .reject(&:blank?)
                                .uniq

    raise StandardError, 'No sample_number found in file' if sample_numbers.blank?
    raise StandardError,
          "Multiple sample_number values found in file: #{sample_numbers.join(', ')}" if sample_numbers.size > 1

    sample_numbers.first
  end

  def duplicate_campaign?(project_code, sample_number)
    return false if project_code.blank? || sample_number.blank?

    WhatsappOutbound.exists?(
      project_code: project_code,
      sample_number: sample_number,
      status: 'sent'
    )
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')
  end

  def safe_row_log(row)
    return {} if row.blank?

    {
      username: row[:username],
      panelistid: row[:panelistid],
      samplenumber: row[:samplenumber]
    }
  end

  def cleanup_file(file_path)
    return if file_path.blank?
    return unless File.exist?(file_path)

    File.delete(file_path)
    Rails.logger.info("[SendWhatsappMessagesWorker] Deleted temp file #{file_path}")
  rescue StandardError => e
    Rails.logger.error(
      "[SendWhatsappMessagesWorker] Could not delete temp file #{file_path}: #{e.class} - #{e.message}"
    )
  end
end
