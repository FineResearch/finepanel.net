# frozen_string_literal: true

require 'csv'

class SyncUsersWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path)
    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      next unless row[1].present?

      new_user = User.find_or_create_by(encrypted_email: row[1], hash_respid: row[2], spanel: row[3])
      if new_user.errors.present?
        error_msg = new_user.encrypted_email + ' ' + new_user.errors.first[1]
        Rails.logger.info(error_msg)
      end
    end

    File.delete(feed_file_path)
    File.delete(file_path)
  end
end
