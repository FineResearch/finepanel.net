# frozen_string_literal: true

require 'csv'

class SyncUsersWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path)
    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      next unless row[1].present?

      new_user = User.find_or_initialize_by(encrypted_email: row[1])
      new_user.hash_respid = row[2]
      new_user.spanel = row[3]
      new_user.save

      if new_user.errors.present?
        error_msg = new_user.encrypted_email + ' ' + new_user.errors.first[1]
        Rails.logger.info(error_msg)
      end
    end

    File.delete(feed_file_path)
    File.delete(file_path)
  end
end
