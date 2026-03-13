module Api
  module V1
    class WebhooksController < ApiController
      def handle_whatsapp_response
        if request.get?
          handle_webhook_config
        else
          handle_inbound_message
        end
      end

      private

      def handle_webhook_config
        mode = params['hub.mode']
        token = params['hub.verify_token']
        challenge = params['hub.challenge']

        if mode && token
          if mode == 'subscribe' && token == 'FINEPANEL'
            puts 'WEBHOOK_VERIFIED'
            render plain: challenge, status: 200
          else
            head :forbidden
          end
        else
          head :bad_request
        end
      end

      def handle_inbound_message
        payload = params.to_unsafe_h

        contact_information = payload.dig('entry', 0, 'changes', 0, 'value', 'contacts', 0)
        message_information = payload.dig('entry', 0, 'changes', 0, 'value', 'messages', 0)

        unless contact_information || message_information
          Rails.logger.info("[WhatsAppInbound] No contact/message info. Payload: #{payload}")
          return head :ok
        end

        wa_number = contact_information&.dig('wa_id')
        profile_name = contact_information&.dig('profile', 'name')
        message_type = message_information&.dig('type')
	from_number = message_information&.dig('from')
	timestamp = message_information&.dig('timestamp')

	message_body =
	message_information&.dig('text', 'body') ||
	message_information&.dig('button', 'text') ||
	message_information&.dig('interactive', 'button_reply', 'title') ||
	message_information&.dig('interactive', 'list_reply', 'title')

	message_id = message_information&.dig('id')

        user = nil
	last_outbound = nil

	if wa_number.present?
	user = User.where("whatsapp_number LIKE ?", "%#{wa_number}%").first
	last_outbound = WhatsappOutbound.where(user_id: user.id).order(created_at: :desc).first if user
	end

Rails.logger.info(
  "[WhatsAppInbound] message_id=#{message_id} from=#{wa_number} profile_name=#{profile_name} " \
  "type=#{message_type} body=#{message_body} user_id=#{user&.id} " \
  "last_project_code=#{last_outbound&.project_code} " \
  "last_subject=#{last_outbound&.subject} " \
  "last_survey_link=#{last_outbound&.survey_link}"
)
WhatsappMailer.new.inbound_message_alert(
  profile_name: profile_name,
  from_number: wa_number,
  user_id: user&.id,
  message_body: message_body,
  message_id: message_id,
  message_type: message_type,
  project_code: last_outbound&.project_code,
  survey_subject: last_outbound&.subject,
  duration: last_outbound&.duration,
  incentive: last_outbound&.incentive,
  sent_by: last_outbound&.sent_by,
  survey_link: last_outbound&.survey_link,
  main_survey_link: last_outbound&.main_survey_link
)

	head :ok
      rescue StandardError => e
        Rails.logger.error("[WhatsAppInbound] Error: #{e.class} - #{e.message}")
        head :ok
      end
    end
  end
end
