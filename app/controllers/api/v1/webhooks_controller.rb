module Api
  module V1
    class WebhooksController < ApiController

      def handle_whatsapp_response
        if request.get?
          handle_webhook_config
        else
          send_whatsapp_response
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

      def send_whatsapp_response
        contact_information = params.dig('entry', 0, 'changes', 0, 'value', 'contacts', 0)

        if contact_information
          wa_number = contact_information['wa_id']
          user = User.where("whatsapp_number LIKE ?", "%#{wa_number}%").first
          return unless user

          send_whatsapp_message(user)
        end

        head :ok
      end

      def send_whatsapp_message(user)
        user_language = user.language || 'es'
        wp_language = user_language.include?('por') ? 'pt_BR' : user_language

        client = WhatsApp::Client.new

        begin
          client.send_message(
            to_number: user.whatsapp_number,
            parameters: [build_whatsapp_attributes],
            language: wp_language,
            template: 'support_response_template'
          )
        rescue StandardError => e
          Rails.logger.error("[SendWhatsappResponse] Error Sending Whatsapp response #{e}")
        end
      end

      def build_whatsapp_attributes
        support_number = ENV['WHATSAPP_SUPPORT_NUMBER'] || '+5491130321213' # Diego Casavarilla number
        support_text = "https://api.whatsapp.com/send?phone=#{support_number}"

        { type: 'text', text: support_text }
      end
    end
  end
end
