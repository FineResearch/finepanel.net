# frozen_string_literal: true

require 'csv'

class PushNotificationsWorker
  include Sidekiq::Worker

  def perform(users, message)
    PushNotifier.new(users, message).send_notification
  end
end
