class Internal::Whatsapp::ConversationsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_internal_access!
  before_action :set_internal_user
  before_action :set_conversation, only: [:show, :send_text, :send_template, :resolve, :reopen]
  before_action :authorize_conversation!, only: [:show, :send_text, :send_template, :resolve, :reopen]

  def index
    scope = WhatsappConversation.recent_first

    if operator_user?
      scope = scope.where(project_code: allowed_project_codes)
    end

    if params[:project_code].present?
      scope = scope.where(project_code: params[:project_code].to_s)
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

    conversations = scope.limit(limit_param)

    render json: {
      success: true,
      conversations: conversations.map { |conversation| serialize_conversation_summary(conversation) }
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

  def serialize_conversation_summary(conversation)
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
      conversation_window_status: policy.conversation_window_status
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
