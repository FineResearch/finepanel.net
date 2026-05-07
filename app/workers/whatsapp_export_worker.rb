require "csv"
require "fileutils"

class WhatsappExportWorker
  include Sidekiq::Worker
  sidekiq_options retry: 1

  HEADERS = [
    "estado",
    "project_code",
    "panelist_id",
    "pais",
    "ultima_respuesta_respondida",
    "momento_ultima_respuesta",
    "primera_respuesta_optin",
    "primera_respuesta_template",
    "ultima_respuesta_panelista",
    "ultima_respuesta_operador",
    "extracto_conversacion",
    "nombre",
    "apellido",
    "survey_subject",
    "duration",
    "incentive",
    "sent_by",
    "sample_number",
    "template_name",
    "template_language",
    "window_status"
  ].freeze

  def perform(internal_user_id, email, filters = {})
    internal_user = InternalUser.find(internal_user_id)

    dir = Rails.root.join("public", "exports", "whatsapp")
    FileUtils.mkdir_p(dir)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "whatsapp_export_#{timestamp}_#{SecureRandom.hex(4)}.csv"
    file_path = dir.join(filename)

    scope = WhatsappConversation.recent_first

    if internal_user.operator?
      allowed_project_codes = internal_user.internal_user_project_accesses.pluck(:project_code)
      scope = scope.where(project_code: allowed_project_codes)
    end

    scope = apply_sql_filters(scope, filters)

    CSV.open(file_path, "wb") do |csv|
      csv << HEADERS

      scope.find_each(batch_size: 200) do |conversation|
        row = build_row(conversation, filters)
        csv << row if row.present?
      end
    end

    before_message = "[WhatsappExportWorker] before email to=#{email} file_path=#{file_path} file_exists=#{File.exist?(file_path)} file_size=#{File.exist?(file_path) ? File.size(file_path) : 0}"
    puts before_message
    Rails.logger.info(before_message)

    ApplicationMailer.new.send_plain_email(
      to: email,
      from: "auto-export@fine-research.com",
      subject: "WhatsApp export ready",
      text_body: "Your WhatsApp export is attached to this email.",
      attachment_path: file_path.to_s
    )

    after_message = "[WhatsappExportWorker] after email to=#{email}"
    puts after_message
    Rails.logger.info(after_message)
  rescue => e
    Rails.logger.error("[WhatsappExportWorker] Failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?

    begin
      ApplicationMailer.new.send_plain_email(
        to: email,
        from: "auto-export@fine-research.com",
        subject: "WhatsApp export failed",
        text_body: "The WhatsApp export failed.\n\nError: #{e.class} - #{e.message}"
      ) if email.present?
    rescue => mail_error
      Rails.logger.error("[WhatsappExportWorker] failed to send failure email: #{mail_error.class} - #{mail_error.message}")
    end

    raise e
  end

  private

  def apply_sql_filters(scope, filters)
    filters ||= {}

    if filters["project_code"].present?
      scope = scope.where(project_code: filters["project_code"].to_s)
    end

    if filters["panelist_id"].present?
      scope = scope.where(panelist_id: filters["panelist_id"].to_s.strip)
    end

    if filters["status"].present?
      case filters["status"].to_s
      when "open"
        scope = scope.where(resolved_at: nil)
      when "resolved"
        scope = scope.where.not(resolved_at: nil)
      end
    end

    scope
  end

  def build_row(conversation, filters)
    context = serialize_context(conversation)

    export_country =
      context[:panelist_country].presence ||
      context["panelist_country"].presence ||
      conversation.try(:panelist_country).presence ||
      conversation.try(:user).try(:country).presence

    return nil unless passes_ruby_filters?(context, export_country, filters)

    messages = conversation.whatsapp_messages.order(:created_at).last(20)
    inbound = messages.select(&:inbound?)
    outbound = messages.select(&:outbound?)

    optin = inbound.find { |m| m.message_body.to_s.strip.downcase == "ok" }
    first_project = inbound.first
    last_inbound = inbound.last
    last_outbound = outbound.select { |m| m.source == "agent" }.last

    last_10 = messages.last(10).map do |m|
      text = m.message_body.to_s.gsub("\n", " ")
      m.source == "agent" ? "**#{text}**" : text
    end.join(" | ")

    [
      conversation.status,
      conversation.project_code,
      conversation.panelist_id,
      export_country,
      value_from_context(context, :last_inbound_requires_reply) ? "no" : "yes",
      value_from_context(context, :last_inbound_within_24h) ? "24h" : "older",
      optin&.message_body,
      first_project&.message_body,
      last_inbound&.message_body,
      last_outbound&.message_body,
      last_10,
      value_from_context(context, :panelist_first_name),
      value_from_context(context, :panelist_last_name),
      value_from_context(context, :survey_subject),
      value_from_context(context, :duration),
      value_from_context(context, :incentive),
      value_from_context(context, :sent_by),
      value_from_context(context, :sample_number),
      value_from_context(context, :template_name),
      value_from_context(context, :template_language),
      value_from_context(context, :conversation_window_status)
    ]
  end

  def serialize_context(conversation)
    ConversationContextBuilder.new(conversation: conversation).as_json
  rescue => e
    Rails.logger.error("[WhatsappExportWorker] context failed conversation=#{conversation.id}: #{e.class} #{e.message}")
    {}
  end

  def value_from_context(context, key)
    context[key] || context[key.to_s]
  end

  def passes_ruby_filters?(context, export_country, filters)
    filters ||= {}

    if filters["country"].present?
      return false unless export_country.to_s.strip.downcase == filters["country"].to_s.strip.downcase
    end

    if filters["last_reply_type"].present?
      value = value_from_context(context, :last_inbound_reply_type)
      return false unless value.to_s == filters["last_reply_type"].to_s
    end

    if filters["last_reply_answered"].present?
      requires_reply = value_from_context(context, :last_inbound_requires_reply)

      case filters["last_reply_answered"].to_s
      when "yes"
        return false unless requires_reply == false
      when "no"
        return false unless requires_reply == true
      end
    end

    if filters["last_reply_window"].present?
      within_24h = value_from_context(context, :last_inbound_within_24h)

      case filters["last_reply_window"].to_s
      when "within_24h"
        return false unless within_24h == true
      when "older"
        return false unless within_24h == false
      end
    end

    true
  end
end
