# frozen_string_literal: true

require 'csv'
require 'batch_manager'

class SyncUsersWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path)
    Rails.logger.info(
      "Starting SyncUsersWorker, feed_file_path: #{feed_file_path}, file_path: #{file_path}"
    )

    insert_columns = [:encrypted_email, :hash_respid, :spanel, :created_at, :updated_at, :jti]
    discard_conflicts_on = [:encrypted_email]
    batch_size = 5000

    batch_manager = BatchManager.new(User, insert_columns, discard_conflicts_on,
                                     on_conflict_action = :update, batch_size)

    batch = []
    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      encrypted_email = row[1]
      next unless encrypted_email.present?

      unless batch.include?(encrypted_email)
        creation_time = Time.now

        batch_manager.add_to_batch(
          encrypted_email,
          hash_respid = row[2],
          spanel = row[3],
          creation_time,
          creation_time,
          SecureRandom.uuid
        )

        batch.push(encrypted_email)
      end

      batch = [] if batch.size == batch_size
    end

    batch_manager.finish

    File.delete(feed_file_path)
    File.delete(file_path)

    Rails.logger.info("Finished SyncUsersWorker")
  rescue => e
    Rails.logger.error { "SyncUsersWorker error: #{e.message[0, 200]} (#{e.class}" }
  end
end
