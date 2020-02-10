# frozen_string_literal: true

require 'csv'

class SyncActiveUsersLanguageWorker
  include Sidekiq::Worker

  LANGUAGE_CODES = {
    '1046' => 'por',
    '2058' => 'es'
  }.freeze

  def perform(feed_file_path, file_path)
    logger.info(
      "Starting SyncActiveUsersLanguageWorker, feed_file_path: #{feed_file_path}, file_path: #{file_path}"
    )

    users_per_language = {}
    LANGUAGE_CODES.each do |_, v|
      users_per_language[v] = []
    end

    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      email = row[0]
      next unless email.present?

      encrypted_email = Digest::MD5.hexdigest(email)

      language_code = row[1].to_s
      language = LANGUAGE_CODES[language_code]

      users_per_language[language] << encrypted_email if users_per_language[language]
    end

    users_per_language.keys.each do |language|
      emails = users_per_language[language]
      users = User.where(encrypted_email: emails)
      users.update_all(language: language, active_app: true)
    end

    File.delete(feed_file_path)
    File.delete(file_path)

    logger.info("Finished SyncActiveUsersLanguageWorker")
  end

  def logger
    environment = Rails.env

    @logger ||= Logger.new("log/sync_active_users_language_#{environment}.log", 'monthly')
  end
end
