# frozen_string_literal: true

require 'csv'

class PushNotificationsWorker
  include Sidekiq::Worker

  def perform(user_ids, message)
    PushNotifier.new(user_ids, message).send_notification
  end
end
