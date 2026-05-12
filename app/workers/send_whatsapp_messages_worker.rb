# frozen_string_literal: true

require 'csv'
require 'securerandom'
require 'uri'
require 'cgi'
require 'set'

class SendWhatsappMessagesWorker
  include Sidekiq::Worker
  include FilesHelper

  BATCH_SIZE = 500
  DAILY_WHATSAPP_LIMIT = 100000
  CAPACITY_BUFFER = 25
  OPT_IN_TEMPLATE_NAMES = %w[preferencia_es preferencia_pt].freeze

  def perform(file_path, text)
    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Starting worker, feed_file_path=#{file_path}"
    )

    Rails.logger.info("[SendWhatsappMessagesWorker] raw_text=#{text.inspect}")

    csv_content = tab_separated_to_hash(file_path)
    values = fetch_variables(text)
    include_respondent_phone = values.key?(:agregartel)
    @send_report_rows = []

    Rails.logger.info("[SendWhatsappMessagesWorker] parsed_values=#{values.inspect}")
    Rails.logger.info("[SendWhatsappMessagesWorker] include_respondent_phone=#{include_respondent_phone}")

    if csv_content.blank?
      Rails.logger.warn(
        "[SendWhatsappMessagesWorker] Aborting because file has no rows file_path=#{file_path}"
      )
      return
    end

    if reminder_request?(values)
      process_reminder_campaign(csv_content, values)
      return
    end


    if optin_request?(values)
      process_optin_campaign(csv_content, values)
      return
    end

    project_code = values[:codigodelproyecto].to_s.strip
    sample_number = extract_single_sample_number!(csv_content)

    client = WhatsApp::Client.new
    campaign_uuid = SecureRandom.uuid
    campaign_sent_numbers = Set.new

    csv_content.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        process_row(
          row,
          values,
          include_respondent_phone,
          campaign_uuid,
          client,
          campaign_sent_numbers
        )
      rescue StandardError => e
        Rails.logger.error(
          "[SendWhatsappMessagesWorker] Unexpected row-level error row=#{safe_row_log(row)} error=#{e.class} - #{e.message}"
        )
        next
      end
    end

    write_last_send_report!

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

def record_send_report(
  row,
  outcome:,
  reason:,
  user: nil,
  whatsapp_number: nil,
  template_name: nil,
  project_code: nil,
  status: nil,
  error_message: nil
)
  @send_report_rows ||= []

  @send_report_rows << {
    outcome: outcome,
    reason: reason,
    project_code: project_code,
    sample_number: row[:samplenumber],
    panelist_id: row[:panelistid],
    panelist_email: row[:username],
    user_id: user&.id,
    whatsapp_number: whatsapp_number,
    template_name: template_name,
    status: status,
    error_message: error_message
  }
end

def restrict_to_optin?(values)
  values[:restringeaoptin].to_s.strip.upcase != 'NO'
end

def write_last_send_report!
  return if @send_report_rows.blank?

  path = Rails.root.join('tmp', 'last_whatsapp_send_report.csv')

  CSV.open(path, 'w') do |csv|
    csv << %w[
      outcome
      reason
      project_code
      sample_number
      panelist_id
      panelist_email
      user_id
      whatsapp_number
      template_name
      status
      error_message
    ]

    @send_report_rows.each do |row|
      csv << [
        row[:outcome],
        row[:reason],
        row[:project_code],
        row[:sample_number],
        row[:panelist_id],
        row[:panelist_email],
        row[:user_id],
        row[:whatsapp_number],
        row[:template_name],
        row[:status],
        row[:error_message]
      ]
    end
  end

  Rails.logger.info(
    "[SendWhatsappMessagesWorker] Wrote send report path=#{path} rows=#{@send_report_rows.size}"
  )
end

def optin_already_sent_successfully?(whatsapp_number)
  normalized_number = normalize_phone(whatsapp_number)

  WhatsappOutbound.where(status: 'sent')
                  .where(template_name: OPT_IN_TEMPLATE_NAMES)
                  .where(whatsapp_number: normalized_number)
                  .exists?
end

def invitation_template_already_sent_successfully?(project_code, template_name, whatsapp_number)
  normalized_number = normalize_phone(whatsapp_number)

  WhatsappOutbound.where(status: 'sent')
                  .where(project_code: project_code)
                  .where(template_name: template_name)
                  .where(whatsapp_number: normalized_number)
                  .exists?
end


def invalid_whatsapp_number_active?(whatsapp_number)
  normalized_number = normalize_phone(whatsapp_number)

  InvalidWhatsappNumber.where(whatsapp_number: normalized_number, active: true)
                       .where('times_detected >= ?', 2)
                       .exists?
end


def record_optin_skip(row, reason:, user: nil, whatsapp_number: nil, error_message: nil)
  @optin_skip_rows ||= []

  @optin_skip_rows << {
    reason: reason,
    panelist_id: row[:panelistid],
    panelist_email: row[:username],
    sample_number: row[:samplenumber],
    user_id: user&.id,
    whatsapp_number: whatsapp_number,
    error_message: error_message
  }
end

def write_last_optin_skip_report!
  return if @optin_skip_rows.blank?

  path = Rails.root.join('tmp', 'last_optin_skip_report.csv')

  CSV.open(path, 'w') do |csv|
    csv << %w[
      reason
      panelist_id
      panelist_email
      sample_number
      user_id
      whatsapp_number
      error_message
    ]

    @optin_skip_rows.each do |row|
      csv << [
        row[:reason],
        row[:panelist_id],
        row[:panelist_email],
        row[:sample_number],
        row[:user_id],
        row[:whatsapp_number],
        row[:error_message]
      ]
    end
  end

  Rails.logger.info(
    "[SendWhatsappMessagesWorker] Wrote optin skip report path=#{path} rows=#{@optin_skip_rows.size}"
  )
end


def optin_template_name_for_language(language)
  language == 'pt_BR' ? 'preferencia_pt' : 'preferencia_es'
end

  def reminder_request?(values)
    values[:template].to_s.strip.upcase == 'REMINDER'
  end

  def optin_request?(values)
    values[:template].to_s.strip.upcase == 'OPTIN'
  end

  def process_reminder_campaign(csv_content, values)
    project_code = values[:codigodelproyecto].to_s.strip
    raise StandardError, 'Missing CODIGO DEL PROYECTO for reminder' if project_code.blank?

    panelist_ids = csv_content.map { |row| row[:panelistid].to_s.strip }
                             .reject(&:blank?)
                             .uniq

    raise StandardError, 'No panelist_id found in file for reminder' if panelist_ids.blank?

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Processing reminder campaign project_code=#{project_code} panelist_ids_count=#{panelist_ids.size}"
    )

    result = WhatsApp::ReminderSender.new(
      project_code: project_code,
      panelist_ids: panelist_ids,
      text_es: values[:texto_es],
      text_pt: values[:texto_pt],
      internal_user: nil
    ).run

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Reminder results project_code=#{project_code} result=#{result.inspect}"
    )
  end

  def process_optin_campaign(csv_content, values)
    project_code = values[:codigodelproyecto].to_s.strip
    sample_number = extract_single_sample_number!(csv_content)

    client = WhatsApp::Client.new
    campaign_uuid = SecureRandom.uuid
    campaign_sent_numbers = Set.new

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Processing optin campaign project_code=#{project_code} sample_number=#{sample_number}"
    )

    csv_content.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        process_optin_row(
          row,
          values,
          campaign_uuid,
          client,
          campaign_sent_numbers
        )
      rescue StandardError => e
        Rails.logger.error(
          "[SendWhatsappMessagesWorker] Unexpected optin row-level error row=#{safe_row_log(row)} error=#{e.class} - #{e.message}"
        )
        record_send_report(
          row,
          outcome: 'failed',
          reason: 'row_level_error',
          project_code: values[:codigodelproyecto],
          status: 'failed',
          error_message: "#{e.class} - #{e.message}"
        )
        next
      end
    end

    write_last_send_report!

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Finished optin campaign campaign_uuid=#{campaign_uuid} project_code=#{project_code} sample_number=#{sample_number}"
    )
  end

def process_optin_row(row, values, campaign_uuid, client, campaign_sent_numbers)
  Rails.logger.info("[SendWhatsappMessagesWorker] optin_row=#{safe_row_log(row)}")

  username = row[:username].to_s.strip

  if username.blank?
    record_send_report(
      row,
      outcome: 'skipped',
      reason: 'blank_username',
      project_code: values[:codigodelproyecto],
      status: 'skipped'
    )
    return
  end

  user = User.find_from_email(username)

  unless user
    record_send_report(
      row,
      outcome: 'skipped',
      reason: 'user_not_found',
      project_code: values[:codigodelproyecto],
      status: 'skipped'
    )
    return
  end

  whatsapp_number = resolve_row_whatsapp_number(user, row)

  if whatsapp_number.blank? || whatsapp_number == '9' || whatsapp_number.length < 8
    record_send_report(
      row,
      outcome: 'skipped',
      reason: 'invalid_whatsapp_number',
      user: user,
      whatsapp_number: whatsapp_number,
      project_code: values[:codigodelproyecto],
      status: 'skipped'
    )
    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Skipping invalid optin whatsapp_number=#{whatsapp_number} user_id=#{user.id}"
    )
    return
  end

if invalid_whatsapp_number_active?(whatsapp_number)
  record_send_report(
    row,
    outcome: 'skipped',
    reason: 'known_invalid_whatsapp_number',
    user: user,
    whatsapp_number: whatsapp_number,
    project_code: values[:codigodelproyecto],
    status: 'skipped'
  )
  return
end  

language = resolve_language(whatsapp_number)
  template_name = optin_template_name_for_language(language)

  if optin_already_sent_successfully?(whatsapp_number)
    record_send_report(
      row,
      outcome: 'skipped',
      reason: 'already_sent_successfully_to_whatsapp_number',
      user: user,
      whatsapp_number: whatsapp_number,
      template_name: template_name,
      project_code: values[:codigodelproyecto],
      status: 'skipped'
    )
    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Skipping optin already sent successfully whatsapp_number=#{whatsapp_number} user_id=#{user.id} panelist_id=#{row[:panelistid]}"
    )
    return
  end

  if campaign_sent_numbers.include?(whatsapp_number)
    record_send_report(
      row,
      outcome: 'skipped',
      reason: 'duplicate_number_same_campaign',
      user: user,
      whatsapp_number: whatsapp_number,
      template_name: template_name,
      project_code: values[:codigodelproyecto],
      status: 'skipped'
    )
    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Skipping duplicate optin whatsapp_number within same campaign whatsapp_number=#{whatsapp_number} user_id=#{user.id}"
    )
    return
  end

  if capacity_reached_for_number?(whatsapp_number, campaign_sent_numbers)
    record_send_report(
      row,
      outcome: 'skipped',
      reason: 'capacity_reached',
      user: user,
      whatsapp_number: whatsapp_number,
      template_name: template_name,
      project_code: values[:codigodelproyecto],
      status: 'skipped'
    )
    Rails.logger.warn(
      "[SendWhatsappMessagesWorker] Capacity reached, skipping optin whatsapp_number=#{whatsapp_number} user_id=#{user.id} project_code=#{values[:codigodelproyecto]}"
    )
    return
  end

  phone_number_id = resolve_phone_number_id(whatsapp_number)
  from_phone_number = resolve_from_phone_number(whatsapp_number)
  support_email = resolve_support_email(values, whatsapp_number)

  template_param_values = build_optin_template_param_values(
    user: user,
    language: language
  )

  log_template_param_values(template_param_values)
  validate_template_param_values!(template_param_values)

  Rails.logger.info(
    "[SendWhatsappMessagesWorker] Sending optin WhatsApp message to #{whatsapp_number} language=#{language} template=#{template_name}"
  )

  client.send_message(
    phone_number_id: phone_number_id,
    to_number: whatsapp_number,
    parameters: build_whatsapp_params(template_param_values),
    language: language,
    template: template_name
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
    subject: values[:asunto].presence || 'WHATSAPP_OPTIN',
    project_code: values[:codigodelproyecto],
    duration: values[:duracion],
    incentive: values[:moneda_valor],
    sent_by: values[:envia],
    template_name: template_name,
    language: language,
    status: 'sent',
    campaign_uuid: campaign_uuid,
    include_respondent_phone: false
  )

  record_send_report(
    row,
    outcome: 'sent',
    reason: 'sent_successfully',
    user: user,
    whatsapp_number: whatsapp_number,
    template_name: template_name,
    project_code: values[:codigodelproyecto],
    status: 'sent'
  )

  campaign_sent_numbers.add(whatsapp_number)

  WhatsappDeliveryResult.create!(
    project_code: values[:codigodelproyecto],
    sample_number: row[:samplenumber],
    panelist_id: row[:panelistid],
    panelist_email: row[:username],
    whatsapp_number: whatsapp_number,
    status: 'sent'
  )
rescue StandardError => e
  record_send_report(
    row,
    outcome: 'failed',
    reason: 'send_error',
    user: user,
    whatsapp_number: whatsapp_number,
    template_name: template_name,
    project_code: values[:codigodelproyecto],
    status: 'failed',
    error_message: "#{e.class} - #{e.message}"
  )

  handle_failed_whatsapp(
    user: user,
    row: row,
    values: values,
    campaign_uuid: campaign_uuid,
    include_respondent_phone: false,
    whatsapp_number: whatsapp_number,
    language: language,
    phone_number_id: phone_number_id,
    from_phone_number: from_phone_number,
    support_email: support_email,
    main_surveylink: nil,
    template_name: template_name,
    error: e
  )
end

  def process_row(row, values, include_respondent_phone, campaign_uuid, client, campaign_sent_numbers)
    Rails.logger.info("[SendWhatsappMessagesWorker] row=#{safe_row_log(row)}")

    username = row[:username].to_s.strip

    if username.blank?
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'blank_username',
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      return
    end

    user = User.find_from_email(username)

    unless user
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'user_not_found',
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      return
    end

    panelist_record = WhatsappProjectPanelist.find_by(
      project_code: values[:codigodelproyecto],
      panelist_id: row[:panelistid]
    )

    if postponed_recently?(panelist_record)
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'postponed_recently',
        user: user,
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      Rails.logger.info(
        "[SendWhatsappMessagesWorker] Skipping postponed user_id=#{user.id} panelist_id=#{row[:panelistid]} project_code=#{values[:codigodelproyecto]}"
      )
      return
    end

    whatsapp_number = resolve_row_whatsapp_number(user, row)

if restrict_to_optin?(values) && !user.whatsapp_opt_in
  record_send_report(
    row,
    outcome: 'skipped',
    reason: 'not_whatsapp_optin',
    user: user,
    whatsapp_number: whatsapp_number,
    project_code: values[:codigodelproyecto],
    status: 'skipped'
  )
  Rails.logger.info(
    "[SendWhatsappMessagesWorker] Skipping non opt-in user_id=#{user.id} panelist_id=#{row[:panelistid]} project_code=#{values[:codigodelproyecto]}"
  )
  return
end
    if campaign_sent_numbers.include?(whatsapp_number)
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'duplicate_number_same_campaign',
        user: user,
        whatsapp_number: whatsapp_number,
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      Rails.logger.info(
        "[SendWhatsappMessagesWorker] Skipping duplicate whatsapp_number within same campaign whatsapp_number=#{whatsapp_number} user_id=#{user.id} project_code=#{values[:codigodelproyecto]}"
      )
      return
    end

    if whatsapp_number.blank? || whatsapp_number == '9' || whatsapp_number.length < 8
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'invalid_whatsapp_number',
        user: user,
        whatsapp_number: whatsapp_number,
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      Rails.logger.info(
        "[SendWhatsappMessagesWorker] Skipping invalid whatsapp_number=#{whatsapp_number} user_id=#{user.id}"
      )
      return
    end

if invalid_whatsapp_number_active?(whatsapp_number)
  record_send_report(
    row,
    outcome: 'skipped',
    reason: 'known_invalid_whatsapp_number',
    user: user,
    whatsapp_number: whatsapp_number,
    project_code: values[:codigodelproyecto],
    status: 'skipped'
  )
  return
end

    if capacity_reached_for_number?(whatsapp_number, campaign_sent_numbers)
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'capacity_reached',
        user: user,
        whatsapp_number: whatsapp_number,
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      Rails.logger.warn(
        "[SendWhatsappMessagesWorker] Capacity reached, skipping whatsapp_number=#{whatsapp_number} user_id=#{user.id} project_code=#{values[:codigodelproyecto]}"
      )
      return
    end

    language = resolve_language(whatsapp_number)
template_name = template_name_for_language(language, values)    

    if invitation_template_already_sent_successfully?(
      values[:codigodelproyecto],
      template_name,
      whatsapp_number
    )
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'invitation_already_sent_same_project_template',
        user: user,
        whatsapp_number: whatsapp_number,
        template_name: template_name,
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      Rails.logger.info(
        "[SendWhatsappMessagesWorker] Skipping invitation already sent successfully " \
        "project_code=#{values[:codigodelproyecto]} template_name=#{template_name} " \
        "whatsapp_number=#{whatsapp_number} user_id=#{user.id} panelist_id=#{row[:panelistid]}"
      )
      return
    end

    original_survey_link = row[:surveylink].to_s.strip

    if original_survey_link.blank?
      record_send_report(
        row,
        outcome: 'skipped',
        reason: 'blank_survey_link',
        user: user,
        whatsapp_number: whatsapp_number,
        template_name: template_name,
        project_code: values[:codigodelproyecto],
        status: 'skipped'
      )
      return
    end

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
      language: language
    )

    log_template_param_values(template_param_values)
    validate_template_param_values!(template_param_values)

    Rails.logger.info(
      "[SendWhatsappMessagesWorker] Sending WhatsApp message to #{whatsapp_number} language=#{language} template=#{template_name}"
    )

    client.send_message(
      phone_number_id: phone_number_id,
      to_number: whatsapp_number,
      parameters: build_whatsapp_params(template_param_values),
      language: language,
      template: template_name
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
      template_name: template_name,
      language: language,
      status: 'sent',
      campaign_uuid: campaign_uuid,
      include_respondent_phone: include_respondent_phone
    )

    record_send_report(
      row,
      outcome: 'sent',
      reason: 'sent_successfully',
      user: user,
      whatsapp_number: whatsapp_number,
      template_name: template_name,
      project_code: values[:codigodelproyecto],
      status: 'sent'
    )

    campaign_sent_numbers.add(whatsapp_number)

    WhatsappDeliveryResult.create!(
      project_code: values[:codigodelproyecto],
      sample_number: row[:samplenumber],
      panelist_id: row[:panelistid],
      panelist_email: row[:username],
      whatsapp_number: whatsapp_number,
      status: 'sent'
    )
  rescue StandardError => e
    record_send_report(
      row,
      outcome: 'failed',
      reason: 'send_error',
      user: user,
      whatsapp_number: whatsapp_number,
      template_name: template_name,
      project_code: values[:codigodelproyecto],
      status: 'failed',
      error_message: "#{e.class} - #{e.message}"
    )

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
      template_name: template_name,
      error: e
    )
  end

  def postponed_recently?(panelist_record)
    return false if panelist_record.blank?
    return false unless panelist_record.status.to_s == 'postponed'
    return false if panelist_record.message_sent_at.blank?

    panelist_record.message_sent_at > 7.days.ago
  end

  def capacity_reached_for_number?(whatsapp_number, campaign_sent_numbers)
    return false if whatsapp_number.blank?
    return false if recent_unique_whatsapp_sent?(whatsapp_number)
    return false if campaign_sent_numbers.include?(whatsapp_number)

    remaining_capacity <= CAPACITY_BUFFER
  end

  def recent_unique_whatsapp_sent?(whatsapp_number)
    WhatsappOutbound.where(status: 'sent')
                    .where('created_at >= ?', 24.hours.ago)
                    .where(whatsapp_number: whatsapp_number)
                    .exists?
  end

  def remaining_capacity
    [DAILY_WHATSAPP_LIMIT - unique_whatsapp_numbers_last_24h, 0].max
  end

  def unique_whatsapp_numbers_last_24h
    WhatsappOutbound.where(status: 'sent')
                    .where('created_at >= ?', 24.hours.ago)
                    .where.not(whatsapp_number: [nil, ''])
                    .distinct
                    .count(:whatsapp_number)
  end

  def template_name_for_language(language, values = {})
  template_type = values[:template].to_s.strip.upcase

  if template_type == 'QUALI'
    return language == 'pt_BR' ?
      'invitacion_quali_pt' :
      'invitacion_quali_es'
  end

  case language
  when 'pt_BR'
    'survey_invitation_reply_v1'
  else
    'survey_invitation_reply_v1_es'
  end
end

  def optin_template_name_for_language(language)
    language == 'pt_BR' ? 'preferencia_pt' : 'preferencia_es'
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

  def build_template_param_values(user:, values:, language:)
    {
      param_1_professional_title: professional_title_for_language(user, language),
      param_2_person_name: person_name_for_language(user, language),
      param_3_asunto: values[:asunto].to_s.strip,
      param_4_duracion: values[:duracion].to_s.strip,
      param_5_moneda_valor: values[:moneda_valor].to_s.strip,
      param_6_envia: values[:envia].to_s.strip,
      param_7_codigodelproyecto: values[:codigodelproyecto].to_s.strip
    }
  end

  def build_optin_template_param_values(user:, language:)
    {
      param_1_professional_title: professional_title_for_language(user, language),
      param_2_person_name: person_name_for_language(user, language)
    }
  end

  def professional_title_for_language(user, language)
    raw_title = user&.professional_title.to_s.strip
    return raw_title if raw_title.present?

    language == 'pt_BR' ? 'Dr(a).' : 'Dr(a).'
  end

  def person_name_for_language(user, language)
    if language == 'pt_BR'
      preferred = user&.first_name.to_s.strip
      fallback = user&.last_name.to_s.strip
      preferred.presence || fallback
    else
      preferred = user&.last_name.to_s.strip
      fallback = user&.first_name.to_s.strip
      preferred.presence || fallback
    end
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
    template_name:,
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
      template_name: template_name,
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
    template_name:,
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
      template_name: template_name,
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
    phone.start_with?('55') ? 'pt_BR' : 'es_MX'
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

pattern = /^\s*(ASUNTO|CODIGO DEL PROYECTO|DURACION|MONEDA-VALOR|ENVIA|AGREGAR TEL|EMAIL SOPORTE|TEMPLATE|TEXTO-PT|TEXTO-ES|RESTRINGE A OPTIN)\s*:\s*(.*?)\s*$/i    

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


  def resolve_row_whatsapp_number(user, row)
    raw_whatsapp =
      user&.whatsapp_number.presence ||
      row[:wapp_wapp].presence ||
      row[:whatsapp_number].presence ||
      row[:telefono].presence ||
      row[:phone].presence ||
      WhatsappProjectPanelist.where(panelist_id: row[:panelistid])
                             .order(updated_at: :desc)
                             .limit(1)
                             .pluck(:whatsapp_number)
                             .first ||
      WhatsappOutbound.where(panelist_id: row[:panelistid])
                      .order(created_at: :desc)
                      .limit(1)
                      .pluck(:whatsapp_number)
                      .first

    normalize_phone(raw_whatsapp)
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
