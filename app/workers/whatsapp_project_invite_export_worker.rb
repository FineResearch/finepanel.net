require "csv"
require "fileutils"

class WhatsappProjectInviteExportWorker
  include Sidekiq::Worker
  sidekiq_options retry: 1

  HEADERS = [
    "project_code",
    "panelist_id",
    "user_id",
    "whatsapp_number",
    "template_name",
    "template_language",
    "invite_status",
    "invite_sent_at",
    "delivery_status",
    "delivery_error",
    "response_status",
    "first_response_body",
    "first_response_at",
    "last_response_body",
    "last_response_at",
    "included_in_last_invite"
  ].freeze

  def perform(internal_user_id, email, project_code)
    internal_user = InternalUser.find(internal_user_id)
    project_code = project_code.to_s.strip

    raise ArgumentError, "project_code is required" if project_code.blank?

    dir = Rails.root.join("public", "exports", "whatsapp")
    FileUtils.mkdir_p(dir)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "whatsapp_project_invites_#{project_code}_#{timestamp}_#{SecureRandom.hex(4)}.csv"
    file_path = dir.join(filename)

    scope = WhatsappOutbound.where(project_code: project_code)

    if internal_user.operator?
      allowed_project_codes = internal_user.internal_user_project_accesses.pluck(:project_code)
      scope = scope.where(project_code: allowed_project_codes)
    end

    last_campaign_uuid = scope.where.not(campaign_uuid: [nil, ""]).order(created_at: :desc).limit(1).pluck(:campaign_uuid).first

    CSV.open(file_path, "wb") do |csv|
      csv << HEADERS

      scope.order(:created_at).find_each(batch_size: 500) do |outbound|
        csv << build_row(outbound, last_campaign_uuid)
      end
    end

    WhatsappExportMailer.new.export_ready_email(
      to: email,
      file_path: file_path.to_s
    )
  rescue => e
    Rails.logger.error("[WhatsappProjectInviteExportWorker] Failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?

    begin
      WhatsappExportMailer.new.export_failed_email(
        to: email,
        error_message: "#{e.class} - #{e.message}"
      ) if email.present?
    rescue => mail_error
      Rails.logger.error("[WhatsappProjectInviteExportWorker] failed to send failure email: #{mail_error.class} - #{mail_error.message}")
    end

    raise e
  end

  private

  def build_row(outbound, last_campaign_uuid)
    delivery_result = latest_delivery_result(outbound)
    first_response, last_response = responses_for(outbound)

    [
      outbound.project_code,
      outbound.panelist_id,
      outbound.user_id,
      outbound.whatsapp_number,
      outbound.template_name,
      outbound.template_language,
      outbound.status,
      outbound.created_at,
      delivery_result&.status,
      delivery_result&.error_message,
      classify_response(first_response&.message_body),
      first_response&.message_body,
      first_response&.created_at,
      last_response&.message_body,
      last_response&.created_at,
      included_in_last_invite?(outbound, last_campaign_uuid) ? "yes" : "no"
    ]
  end

  def latest_delivery_result(outbound)
    return nil unless outbound.respond_to?(:whatsapp_delivery_results)

    outbound.whatsapp_delivery_results.order(created_at: :desc).first
  rescue
    nil
  end

  def responses_for(outbound)
    number = outbound.whatsapp_number.to_s.gsub(/\D/, "")
    return [nil, nil] if number.blank?

    messages = WhatsappMessage
      .where(direction: "inbound")
      .where("regexp_replace(from_phone_number, '\\D', '', 'g') = ?", number)
      .where("created_at >= ?", outbound.created_at)
      .order(:created_at)

    [messages.first, messages.last]
  end

  def classify_response(body)
    normalized = body.to_s.strip.downcase

    return "No response" if normalized.blank?
    return "Answered 1" if normalized == "1"
    return "Answered 2" if normalized == "2"

    cancel_words = ["cancel", "cancelar", "cancela", "stop", "baja"]
    return "Answered cancel" if cancel_words.include?(normalized)

    "Other"
  end

  def included_in_last_invite?(outbound, last_campaign_uuid)
    return false if last_campaign_uuid.blank?

    outbound.campaign_uuid.to_s == last_campaign_uuid.to_s
  end
end
