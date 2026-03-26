require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)

module Finepanel
  class Application < Rails::Application
    config.load_defaults 5.2

    config.i18n.default_locale = :es
    config.encoding = 'utf-8'

    config.active_job.queue_adapter = :sidekiq
    config.action_mailer.deliver_later_queue_name = :default

    config.assets.paths << Rails.root.join('app', 'assets', 'fonts')

    config.logger = Logger.new(STDOUT)

    # Dynamed se manejará por routing/host, no por middleware global,
    # para no interferir con requests normales de Rails.
  end
end
