require 'net/http'
require 'uri'
require 'json'

module WhatsApp
  class Client
    DEFAULT_API_VERSION = 'v23.0'.freeze

    def send_message(phone_number_id: nil, to_number:, parameters:, language:, template:)
      resolved_phone_number_id = phone_number_id.presence || default_phone_number_id
      raise ArgumentError, 'Missing WhatsApp phone number id' if resolved_phone_number_id.blank?

      payload = {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: normalize_to_number(to_number),
        type: 'template',
        template: {
          name: template.to_s,
          language: {
            code: language.to_s
          }
        }
      }

      normalized_parameters = Array(parameters).compact
      if normalized_parameters.present?
        payload[:template][:components] = [
          {
            type: 'body',
            parameters: normalized_parameters
          }
        ]
      end

      post_message(
        phone_number_id: resolved_phone_number_id,
        payload: payload
      )
    end

    def send_text_message(phone_number_id: nil, to_number:, body:)
      resolved_phone_number_id = phone_number_id.presence || default_phone_number_id
      raise ArgumentError, 'Missing WhatsApp phone number id' if resolved_phone_number_id.blank?

      payload = {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: normalize_to_number(to_number),
        type: 'text',
        text: {
          preview_url: false,
          body: body.to_s
        }
      }

      post_message(
        phone_number_id: resolved_phone_number_id,
        payload: payload
      )
    end

    private

    def post_message(phone_number_id:, payload:)
      uri = URI.parse("#{api_base_url}/#{phone_number_id}/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Authorization'] = "Bearer #{access_token}"
      request['Content-Type'] = 'application/json'
      request.body = payload.to_json

      response = http.request(request)
      parsed_body = parse_response_body(response.body)

      if response.code.to_i >= 400
        raise StandardError, "WhatsApp API error #{response.code}: #{parsed_body}"
      end

      parsed_body
    end

    def parse_response_body(body)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    def normalize_to_number(number)
      number.to_s.gsub(/\D/, '')
    end

    def api_base_url
      "https://graph.facebook.com/#{api_version}"
    end

    def api_version
      env_value('WHATSAPP_API_VERSION').presence || DEFAULT_API_VERSION
    end

    def default_phone_number_id
      env_value('WHATSAPP_ID_NUMBER')
    end

    def access_token
      token = env_value('WHATSAPP_AUTH_TOKEN')
      raise ArgumentError, 'Missing WhatsApp auth token' if token.blank?

      token
    end

    def env_value(key)
      ENV[key].presence || secrets_hash[key]
    end

    def secrets_hash
      @secrets_hash ||= begin
        raw = ENV['SECRETS'].to_s
        raw.present? ? JSON.parse(raw) : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
