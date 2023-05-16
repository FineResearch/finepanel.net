# frozen_string_literal: true

module WhatsApp
  class Client
    include HTTParty

    API_URL        = 'https://graph.facebook.com/v16.0'
    API_ID_NUMBER  = ENV['WHATSAPP_ID_NUMBER'] || 'WHATSAPP_ID_NUMBER'
    API_AUTH_TOKEN = ENV['WHATSAPP_AUTH_TOKEN'] || 'WHATSAPP_AUTH_TOKEN'

    def initialize
      set_base_uri
      set_headers
    end

    def send_message(to_number:, parameters:, language:, template:)
      response = self.class.post("/#{API_ID_NUMBER}/messages", {
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

      response_obj = JSON.parse(response.body)
      error = response_obj['error']
      raise StandardError.new(error) if error
    end

    private

    def set_base_uri
      self.class.base_uri API_URL
    end

    def set_headers
      self.class.headers 'Authorization' => "Bearer #{API_AUTH_TOKEN}",
                         'Content-Type' => 'application/json'
    end
  end
end
