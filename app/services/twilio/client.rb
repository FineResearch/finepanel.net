# frozen_string_literal: true

module Twilio
  class Client
    require 'twilio-ruby'

    def initialize(from_number: ENV['TWILIO_DEFAULT_NUMBER'])
      @from_number = from_number
    end

    def send_message(to_number:, message:)
      client.messages.create(
        from: "whatsapp:#{@from_number}",
        to: "whatsapp:#{to_number}",
        body: message
      )
    end

    private

    def client
      @client ||= Twilio::REST::Client.new(
        ENV['TWILIO_ACCOUNT_SID'],
        ENV['TWILIO_AUTH_TOKEN']
      )
    end
  end
end
