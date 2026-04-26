class Internal::Whatsapp::ConversationsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_internal_access!
  before_action :set_internal_user
  before_action :set_conversation, only: [:show, :send_text, :send_template, :send_reminder, :resolve, :reopen]
  before_action :authorize_conversation!, only: [:show, :send_text, :send_template, :send_reminder, :resolve, :reopen]

  DAILY_WHATSAPP_LIMIT = 2000

  def index
    scope = WhatsappConversation.recent_first

    if operator_user?
      scope = scope.where(project_code: allowed_project_codes)
    end

    if params[:project_code].present?
      scope = scope.where(project_code: params[:project_code].to_s)
    end


if params[:panelist_id].present?
  scope = scope.where(panelist_id: params[:panelist_id].to_s.strip)
end


    if truthy_param?(params[:unread])
      scope = scope.where(has_unread_messages: true)
    end

    if params[:status].present?
      case params[:status].to_s
      when 'open'
        scope = scope.where(resolved_at: nil)
      when 'resolved'
        scope = scope.where.not(resolved_at: nil)
      end
    end

    conversations = scope.limit(1000)

    serialized = conversations.map { |conversation| serialize_conversation_summary(conversation) }

    if params[:last_reply_type].present?
      serialized = apply_last_reply_type_filter(serialized, params[:last_reply_type].to_s)
    end

    if params[:last_reply_answered].present?
      serialized = apply_last_reply_answered_filter(serialized, params[:last_reply_answered].to_s)
    end

    if params[:last_reply_window].present?
      serialized = apply_last_reply_window_filter(serialized, params[:last_reply_window].to_s)
    end

    if params[:country].present?
      serialized = apply_country_filter(serialized, params[:country].to_s)
    end

    serialized = serialized.first(limit_param)

    render json: {
      success: true,
      conversations: serialized
    }
  end

  def show
    render json: {
      success: true,
      conversation: serialize_conversation_detail(@conversation)
    }
  end

  def send_text
    result = ManualMessageSender.new(
      internal_user: @internal_user,
      conversation: @conversation
    ).send_free_text!(body: params[:body])

    if result.success?
      render json: {
        success: true,
        conversation: serialize_conversation_detail(@conversation.reload),
        sent_message: serialize_message(result.whatsapp_message),
        provider_response: result.provider_response
      }
    else
      render json: {
        success: false,
        error_code: result.error_code,
        message: result.message
      }, status: :unprocessable_entity
    end
  end

  def project_metrics
    outbound_scope = WhatsappOutbound.all
    panelists_scope = WhatsappProjectPanelist.all

    if operator_user?
      outbound_scope = outbound_scope.where(project_code: allowed_project_codes)
      panelists_scope = panelists_scope.where(project_code: allowed_project_codes)
    end

    outbound = outbound_scope
                 .group(:project_code)
                 .select(
                   :project_code,
                   "COUNT(*) FILTER (WHERE status = 'sent') as sent_messages",
                   "COUNT(*) FILTER (WHERE status = 'failed') as failed_messages",
                   "COUNT(*) FILTER (WHERE status = 'invalid_whatsapp') as invalid_messages",
                   "COUNT(DISTINCT panelist_id) FILTER (WHERE status = 'sent') as contacted_panelists",
                   "COUNT(*) FILTER (WHERE status = 'sent' AND created_at >= NOW() - INTERVAL '24 hours') as sent_messages_last_24h",
                   "COUNT(DISTINCT panelist_id) FILTER (WHERE status = 'sent' AND created_at >= NOW() - INTERVAL '24 hours') as contacted_panelists_last_24h",
                   "COUNT(DISTINCT whatsapp_number) FILTER (WHERE status = 'sent' AND created_at >= NOW() - INTERVAL '24 hours' AND whatsapp_number IS NOT NULL AND BTRIM(whatsapp_number) <> '') as unique_whatsapp_numbers_last_24h"
                 )

    panelists = panelists_scope
                  .group(:project_code)
                  .select(
                    :project_code,
                    "COUNT(DISTINCT panelist_id) FILTER (WHERE reply_received_at IS NOT NULL) as responded_panelists",
                    "COUNT(DISTINCT panelist_id) FILTER (WHERE agent_intervened = true) as agent_interactions",
                    "COUNT(DISTINCT panelist_id) FILTER (WHERE reply_received_at >= NOW() - INTERVAL '24 hours') as responded_panelists_last_24h"
                  )

    outbound_summary = outbound_scope
                         .select(
                           "COUNT(*) FILTER (WHERE status = 'sent') as total_sent_messages",
                           "COUNT(*) FILTER (WHERE status = 'failed') as total_failed_messages",
                           "COUNT(*) FILTER (WHERE status = 'invalid_whatsapp') as total_invalid_messages",
                           "COUNT(DISTINCT panelist_id) FILTER (WHERE status = 'sent') as total_contacted_panelists",
                           "COUNT(*) FILTER (WHERE status = 'sent' AND created_at >= NOW() - INTERVAL '24 hours') as total_sent_messages_last_24h",
                           "COUNT(DISTINCT panelist_id) FILTER (WHERE status = 'sent' AND created_at >= NOW() - INTERVAL '24 hours') as total_contacted_panelists_last_24h",
                           "COUNT(DISTINCT whatsapp_number) FILTER (WHERE status = 'sent' AND created_at >= NOW() - INTERVAL '24 hours' AND whatsapp_number IS NOT NULL AND BTRIM(whatsapp_number) <> '') as unique_whatsapp_numbers_last_24h"
                         )
                         .take

    panelists_summary = panelists_scope
                          .select(
                            "COUNT(DISTINCT panelist_id) FILTER (WHERE reply_received_at IS NOT NULL) as total_responded_panelists",
                            "COUNT(DISTINCT panelist_id) FILTER (WHERE agent_intervened = true) as total_agent_interactions",
                            "COUNT(DISTINCT panelist_id) FILTER (WHERE reply_received_at >= NOW() - INTERVAL '24 hours') as total_responded_panelists_last_24h"
                          )
                          .take

    metrics = {}

    outbound.each do |row|
      metrics[row.project_code] ||= {}
      metrics[row.project_code].merge!(
        sent_messages: row.sent_messages.to_i,
        failed_messages: row.failed_messages.to_i,
        invalid_messages: row.invalid_messages.to_i,
        contacted_panelists: row.contacted_panelists.to_i,
        sent_messages_last_24h: row.sent_messages_last_24h.to_i,
        contacted_panelists_last_24h: row.contacted_panelists_last_24h.to_i,
        unique_whatsapp_numbers_last_24h: row.unique_whatsapp_numbers_last_24h.to_i
      )
    end

    panelists.each do |row|
      metrics[row.project_code] ||= {}
      metrics[row.project_code].merge!(
        responded_panelists: row.responded_panelists.to_i,
        agent_interactions: row.agent_interactions.to_i,
        responded_panelists_last_24h: row.responded_panelists_last_24h.to_i
      )
    end

    used_capacity = outbound_summary&.unique_whatsapp_numbers_last_24h.to_i
    remaining_capacity = DAILY_WHATSAPP_LIMIT - used_capacity
    remaining_capacity = 0 if remaining_capacity.negative?

    render json: {
      success: true,
      summary: {
        total_sent_messages: outbound_summary&.total_sent_messages.to_i,
        total_failed_messages: outbound_summary&.total_failed_messages.to_i,
        total_invalid_messages: outbound_summary&.total_invalid_messages.to_i,
        total_contacted_panelists: outbound_summary&.total_contacted_panelists.to_i,
        total_responded_panelists: panelists_summary&.total_responded_panelists.to_i,
        total_agent_interactions: panelists_summary&.total_agent_interactions.to_i,
        total_sent_messages_last_24h: outbound_summary&.total_sent_messages_last_24h.to_i,
        total_contacted_panelists_last_24h: outbound_summary&.total_contacted_panelists_last_24h.to_i,
        total_responded_panelists_last_24h: panelists_summary&.total_responded_panelists_last_24h.to_i,
        unique_whatsapp_numbers_last_24h: used_capacity,
        remaining_capacity: remaining_capacity,
        daily_limit: DAILY_WHATSAPP_LIMIT
      },
      metrics: metrics
    }
  end

  def send_template
    result = ManualMessageSender.new(
      internal_user: @internal_user,
      conversation: @conversation
    ).send_template!(
      template_name: params[:template_name],
      template_language: params[:template_language].presence || 'es',
      parameters: normalized_template_parameters
    )

    if result.success?
      render json: {
        success: true,
        conversation: serialize_conversation_detail(@conversation.reload),
        sent_message: serialize_message(result.whatsapp_message),
        provider_response: result.provider_response
      }
    else
      render json: {
        success: false,
        error_code: result.error_code,
        message: result.message
      }, status: :unprocessable_entity
    end
  end

def export
  scope = WhatsappConversation.recent_first

  if operator_user?
    scope = scope.where(project_code: allowed_project_codes)
  end

  if params[:project_code].present?
    scope = scope.where(project_code: params[:project_code].to_s)
  end

  if params[:panelist_id].present?
    scope = scope.where(panelist_id: params[:panelist_id].to_s.strip)
  end

  if params[:status].present?
    case params[:status]
    when 'open'
      scope = scope.where(resolved_at: nil)
    when 'resolved'
      scope = scope.where.not(resolved_at: nil)
    end
  end

  # 🔹 PAGINACIÓN + LÍMITE
  max_limit = 10_000
  requested_limit = params[:limit].to_i

  export_limit =
    if requested_limit <= 0
      max_limit
    elsif requested_limit > max_limit
      max_limit
    else
      requested_limit
    end

  page = params[:page].to_i
  page = 1 if page <= 0

  offset = (page - 1) * export_limit

  conversations = scope.limit(export_limit).offset(offset)

  csv = CSV.generate(headers: true) do |csv|
    csv << [
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
    ]

    conversations.each do |c|
      context = serialize_conversation_context(c)

      messages = c.whatsapp_messages.chronological

      inbound = messages.select(&:inbound?)
      outbound = messages.select(&:outbound?)

      # 🔹 OPTIN (OK)
      optin = inbound.find { |m| m.message_body.to_s.strip.downcase == "ok" }

      # 🔹 primera respuesta proyecto
      first_project = inbound.first

      # 🔹 últimas
      last_inbound = inbound.last
      last_outbound = outbound.select { |m| m.source == 'agent' }.last

      # 🔹 extracto últimas 10
      last_10 = messages.last(10).map do |m|
        text = m.message_body.to_s.gsub("\n", " ")
        m.source == 'agent' ? "**#{text}**" : text
      end.join(" | ")

      # 🔹 COUNTRY FALLBACK (clave para OPTIN)
      export_country =
        context[:panelist_country].presence ||
        (c.respond_to?(:panelist_country) ? c.panelist_country : nil).presence ||
        (c.respond_to?(:user) && c.user&.country).presence

      csv << [
        c.status,
        c.project_code,
        c.panelist_id,
        export_country,
        context[:last_inbound_requires_reply] ? "no" : "yes",
        context[:last_inbound_within_24h] ? "24h" : "older",
        optin&.message_body,
        first_project&.message_body,
        last_inbound&.message_body,
        last_outbound&.message_body,
        last_10,
        context[:panelist_first_name],
        context[:panelist_last_name],
        context[:survey_subject],
        context[:duration],
        context[:incentive],
        context[:sent_by],
        context[:sample_number],
        context[:template_name],
        context[:template_language],
        context[:conversation_window_status]
      ]
    end
  end

  send_data csv,
            filename: "whatsapp_export_p#{page}_#{Time.now.to_i}.csv",
            type: "text/csv"
end
  send_data csv,
            filename: "whatsapp_inbox_export_#{Time.now.to_i}.csv",
            type: "text/csv"
end




  def resolve
    @conversation.mark_resolved!(@internal_user)

    render json: {
      success: true,
      conversation: serialize_conversation_detail(@conversation.reload)
    }
  end

  def reopen
    @conversation.reopen!

    render json: {
      success: true,
      conversation: serialize_conversation_detail(@conversation.reload)
    }
  end

  def send_reminder
  result = ManualMessageSender.new(
    internal_user: @internal_user,
    conversation: @conversation
  ).send_reminder!

  if result.success?
    render json: {
      success: true,
      conversation: serialize_conversation_detail(@conversation.reload),
      sent_message: serialize_message(result.whatsapp_message),
      provider_response: result.provider_response
    }
  else
    render json: {
      success: false,
      error_code: result.error_code,
      message: result.message
    }, status: :unprocessable_entity
  end
end

  private

  def authenticate_internal_access!
    return if current_user.present?
    return if header_internal_user_present_and_active?

    authenticate_user!
  end

  def header_internal_user_present_and_active?
    email =
      request.headers['X-Internal-User-Email'].presence ||
      params[:internal_user_email].presence

    return false if email.blank?

    InternalUser.active.exists?(email: email.to_s.strip.downcase)
  end

  def set_internal_user
    email =
      current_user&.email.presence ||
      request.headers['X-Internal-User-Email'].presence ||
      params[:internal_user_email].presence

    @internal_user = InternalUser.active.find_by(email: email.to_s.strip.downcase)

    return if @internal_user.present?

    render json: {
      success: false,
      error_code: 'internal_user_not_found',
      message: 'Internal user not found'
    }, status: :unauthorized
  end

  def set_conversation
    @conversation = WhatsappConversation.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error_code: 'conversation_not_found',
      message: 'Conversation not found'
    }, status: :not_found
  end

  def authorize_conversation!
    return if performed?

    policy = ConversationPolicy.new(
      internal_user: @internal_user,
      conversation: @conversation
    )

    return if policy.can_view?

    render json: {
      success: false,
      error_code: 'forbidden',
      message: 'You do not have access to this conversation'
    }, status: :forbidden
  end

  def operator_user?
    @internal_user.present? && @internal_user.operator?
  end

  def allowed_project_codes
    @internal_user.internal_user_project_accesses.pluck(:project_code)
  end

  def limit_param
    raw = params[:limit].to_i
    return 50 if raw <= 0
    return 200 if raw > 200

    raw
  end

  def truthy_param?(value)
    %w[1 true yes].include?(value.to_s.downcase)
  end

  def normalized_template_parameters
    raw = params[:parameters]
    return [] if raw.blank?
    return raw.to_unsafe_h.values if raw.is_a?(ActionController::Parameters)

    raw
  end

  def apply_last_reply_type_filter(rows, filter_value)
    case filter_value
    when 'one'
      rows.select { |row| row[:last_inbound_reply_type] == 'one' }
    when 'two'
      rows.select { |row| row[:last_inbound_reply_type] == 'two' }
    when 'other'
      rows.select { |row| row[:last_inbound_reply_type] == 'other' }
    else
      rows
    end
  end

  def apply_last_reply_answered_filter(rows, filter_value)
    case filter_value
    when 'yes'
      rows.select { |row| row[:last_inbound_requires_reply] == false }
    when 'no'
      rows.select { |row| row[:last_inbound_requires_reply] == true }
    else
      rows
    end
  end

  def apply_last_reply_window_filter(rows, filter_value)
    case filter_value
    when 'within_24h'
      rows.select { |row| row[:last_inbound_within_24h] == true }
    when 'older'
      rows.select { |row| row[:last_inbound_within_24h] == false }
    else
      rows
    end
  end

  def apply_country_filter(rows, filter_value)
    normalized_filter = filter_value.to_s.strip.downcase
    return rows if normalized_filter.blank?

    rows.select do |row|
      row[:panelist_country].to_s.strip.downcase == normalized_filter
    end
  end

  def serialize_conversation_summary(conversation)
    policy = ConversationPolicy.new(
      internal_user: @internal_user,
      conversation: conversation
    )

    context = serialize_conversation_context(conversation)

    {
      id: conversation.id,
      panelist_id: conversation.panelist_id,
      project_code: conversation.project_code,
      status: conversation.status,
      has_unread_messages: conversation.has_unread_messages,
      last_inbound_at: conversation.last_inbound_at,
      last_outbound_at: conversation.last_outbound_at,
      last_message_at: conversation.last_message_at,
      window_expires_at: conversation.window_expires_at,
      resolved_at: conversation.resolved_at,
      resolved_by_user_id: conversation.resolved_by_user_id,
      allowed_actions: policy.allowed_actions,
      conversation_window_status: policy.conversation_window_status,
      requires_human_follow_up: context[:requires_human_follow_up],
      last_inbound_reply_type: context[:last_inbound_reply_type],
      last_inbound_requires_reply: context[:last_inbound_requires_reply],
      last_inbound_within_24h: context[:last_inbound_within_24h],
      panelist_country: context[:panelist_country]
    }
  end

  def serialize_conversation_detail(conversation)
    policy = ConversationPolicy.new(
      internal_user: @internal_user,
      conversation: conversation
    )

    {
      id: conversation.id,
      panelist_id: conversation.panelist_id,
      project_code: conversation.project_code,
      status: conversation.status,
      has_unread_messages: conversation.has_unread_messages,
      last_inbound_at: conversation.last_inbound_at,
      last_outbound_at: conversation.last_outbound_at,
      last_message_at: conversation.last_message_at,
      window_expires_at: conversation.window_expires_at,
      resolved_at: conversation.resolved_at,
      resolved_by_user_id: conversation.resolved_by_user_id,
      allowed_actions: policy.allowed_actions,
      conversation_window_status: policy.conversation_window_status,
      conversation_context: serialize_conversation_context(conversation),
      messages: conversation.whatsapp_messages.chronological.map { |message| serialize_message(message) }
    }
  end

  def serialize_conversation_context(conversation)
    ConversationContextBuilder.new(conversation: conversation).as_json
  rescue => e
    Rails.logger.error("[WhatsappInbox] conversation_context failed for conversation=#{conversation.id}: #{e.class} #{e.message}")
    {}
  end

  def serialize_message(message)
    return nil if message.blank?

    {
      id: message.id,
      direction: message.direction,
      source: message.source,
      message_body: message.message_body,
      template_name: message.template_name,
      template_language: message.template_language,
      internal_user_id: message.internal_user_id,
      created_at: message.created_at
    }
  end
end
