# frozen_string_literal: true

require 'uri'
require 'cgi'

module WhatsApp
  class TrackedLinkBuilder
    TRACKING_HOST = 'survey-wp.finepanel.net'.freeze
    ORIGINAL_HOST = 'survey.confirmit.com'.freeze

    def self.tracked_link(original_link)
      return nil if original_link.blank?

      uri = URI.parse(original_link)
      uri.host = TRACKING_HOST
      uri.to_s
    end

    def self.final_survey_redirect_link(original_link, whatsapp_number)
      final_redirect_link(
        original_link: original_link,
        whatsapp_number: whatsapp_number,
        extra_params: { 'wp' => '1' }
      )
    end

    def self.final_cancel_redirect_link(original_link, whatsapp_number)
      final_redirect_link(
        original_link: original_link,
        whatsapp_number: whatsapp_number,
        extra_params: { 'exit' => 'cancelar' }
      )
    end

    def self.extract_parts(original_link)
      return {} if original_link.blank?

      uri = URI.parse(original_link)
      params = CGI.parse(uri.query.to_s)

      {
        path: uri.path,
        r: params['r']&.first,
        s: params['s']&.first
      }
    end

    def self.final_redirect_link(original_link:, whatsapp_number:, extra_params:)
      return nil if original_link.blank?

      uri = URI.parse(original_link)
      uri.host = ORIGINAL_HOST

      params = CGI.parse(uri.query.to_s)
      params['l'] = [language_code_for(whatsapp_number)]

      extra_params.each do |key, value|
        params[key] = [value]
      end

      uri.query = URI.encode_www_form(flatten_params(params))
      uri.to_s
    end
    private_class_method :final_redirect_link

    def self.language_code_for(whatsapp_number)
      normalized = whatsapp_number.to_s.gsub(/\D/, '')
      normalized.start_with?('55') ? '1046' : '2058'
    end

    def self.flatten_params(params)
      params.each_with_object([]) do |(key, values), array|
        Array(values).each do |value|
          array << [key, value]
        end
      end
    end
    private_class_method :flatten_params
  end
end
