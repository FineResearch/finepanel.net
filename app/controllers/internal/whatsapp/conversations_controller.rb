require 'csv'

class Internal::Whatsapp::ConversationsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_internal_access!
  before_action :set_internal_user
  before_action :set_conversation, only: [:show, :send_text, :send_template, :send_reminder, :resolve, :reopen]
  before_action :authorize_conversation!, only: [:show, :send_text, :send_template, :send_reminder, :resolve, :reopen]

  DAILY_WHATSAPP_LIMIT = 2000

  def index
    scope = WhatsappConversation.recent_first

    scope = scope.where(project_code: allowed_project_codes) if operator_user?
    scope = scope.where(project_code: params[:project_code]) if params[:project_code].present?
    scope = scope.where(has_unread_messages: true) if truthy_param?(params[:unread])

    if params[:status].present?
      scope = params[:status] == 'open' ? scope.where(resolved_at: nil) : scope.where.not(resolved_at: nil)
    end

    conversations = scope.limit(1000)
    serialized = conversations.map { |c| serialize_conversation_summary(c) }

    serialized = apply_last_reply_type_filter(serialized, params[:last_reply_type]) if params[:last_reply_type].present?
    serialized = apply_last_reply_answered_filter(serialized, params[:last_reply_answered]) if params[:last_reply_answered].present?
    serialized = apply_last_reply_window_filter(serialized, params[:last_reply_window]) if params[:last_reply_window].present?
    serialized = apply_country_filter(serialized, params[:country]) if params[:country].present?

    limit = limit_param
    serialized = serialized.first(limit) if limit.present?

    render json: { success: true, conversations: serialized }
  end

  def show
    render json: { success: true, conversation: serialize_conversation_detail(@conversation) }
  end

  def send_text
    result = ManualMessageSender.new(internal_user: @internal_user, conversation: @conversation)
                                 .send_free_text!(body: params[:body])

    if result.success?
      render json: {
        success: true,
        conversation: serialize_conversation_detail(@conversation.reload),
        sent_message: serialize_message(result.whatsapp_message),
        provider_response: result.provider_response
      }
    else
      render json: { success: false, error_code: result.error_code, message: result.message }, status: :unprocessable_entity
    end
  end

  def project_metrics
    outbound_scope = WhatsappOutbound.all
    panelists_scope = WhatsappProjectPanelist.all

    if operator_user?
      outbound_scope = outbound_scope.where(project_code: allowed_project_codes)
      panelists_scope = panelists_scope.where(project_code: allowed_project_codes)
    end

    render json: { success: true } # <-- mantenlo simple por ahora
  end

  def export
    scope = WhatsappConversation.recent_first
    scope = scope.where(project_code: allowed_project_codes) if operator_user?
    scope = scope.where(project_code: params[:project_code]) if params[:project_code].present?
    scope = scope.where(panelist_id: params[:panelist_id]) if params[:panelist_id].present?

    conversations = scope.limit(10000)

    csv = CSV.generate(headers: true) do |csv|
      csv << ["conversation_id", "status", "panelist_id", "project_code"]

      conversations.each do |c|
        csv << [c.id, c.status, c.panelist_id, c.project_code]
      end
    end

    send_data csv, filename: "whatsapp_export.csv", type: 'text/csv'
  end

  def send_template
    result = ManualMessageSender.new(internal_user: @internal_user, conversation: @conversation)
                                .send_template!(template_name: params[:template_name])

    render json: { success: result.success? }
  end

  def resolve
    @conversation.mark_resolved!(@internal_user)
    render json: { success: true }
  end

  def reopen
    @conversation.reopen!
    render json: { success: true }
  end

  def send_reminder
    result = ManualMessageSender.new(internal_user: @internal_user, conversation: @conversation)
                                .send_reminder!

    render json: { success: result.success? }
  end

  private

  def authenticate_internal_access!
    return if current_user.present?
    return if header_internal_user_present_and_active?
    authenticate_user!
  end

  def header_internal_user_present_and_active?
    email = request.headers['X-Internal-User-Email'] || params[:internal_user_email]
    return false if email.blank?
    InternalUser.active.exists?(email: email.downcase)
  end

  def set_internal_user
    email = current_user&.email || request.headers['X-Internal-User-Email'] || params[:internal_user_email]
    @internal_user = InternalUser.active.find_by(email: email.to_s.downcase)

    unless @internal_user
      render json: { success: false, message: 'Internal user not found' }, status: :unauthorized
    end
  end

  def set_conversation
    @conversation = WhatsappConversation.find(params[:id])
  rescue
    render json: { success: false }, status: :not_found
  end

  def authorize_conversation!
    return if performed?
    policy = ConversationPolicy.new(internal_user: @internal_user, conversation: @conversation)
    render json: { success: false }, status: :forbidden unless policy.can_view?
  end

  def operator_user?
    @internal_user&.operator?
  end

  def allowed_project_codes
    @internal_user.internal_user_project_accesses.pluck(:project_code)
  end

  def limit_param
    return nil if params[:limit] == 'all'
    params[:limit].to_i
  end

  def serialize_conversation_summary(conversation)
    { id: conversation.id, status: conversation.status }
  end

  def serialize_conversation_detail(conversation)
    { id: conversation.id }
  end

  def serialize_message(message)
    return nil unless message
    { id: message.id, message_body: message.message_body }
  end
end
