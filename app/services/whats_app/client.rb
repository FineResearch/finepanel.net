# frozen_string_literal: true

module WhatsApp
  class Client
    include HTTParty

    API_URL = 'https://graph.facebook.com/v16.0'

    def initialize
      set_base_uri
      set_headers
    end

    def send_message(to_number:, parameters:, language:, template:)
      response = self.class.post("/#{api_id_number}/messages", {
        body: {
          messaging_product: 'whatsapp',
          to: to_number,
          type: 'template',
          template: {
            name: template,
            language: {
              code: language
            },
            components: [
              {
                type: 'body',
                parameters: parameters
              }
            ]
          }
        }.to_json
      })

      Rails.logger.info("[WhatsApp::Client] status=#{response.code} body=#{response.body}")

      response_obj = JSON.parse(response.body)
      error = response_obj['error']
      raise StandardError, error.inspect if error
    end

    private

    def api_id_number
      ENV['WHATSAPP_ID_NUMBER'] || 'WHATSAPP_ID_NUMBER'
    end

    def api_auth_token
      ENV['WHATSAPP_AUTH_TOKEN'] || 'WHATSAPP_AUTH_TOKEN'
    end

    def set_base_uri
      self.class.base_uri API_URL
    end

    def set_headers
      self.class.headers(
        'Authorization' => "Bearer #{api_auth_token}",
        'Content-Type' => 'application/json'
      )
    end
  end
end
