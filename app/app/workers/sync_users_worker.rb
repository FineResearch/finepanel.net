# frozen_string_literal: true

require 'csv'
require 'batch_manager'

class SyncUsersWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path)
    logger.info(
      "Starting SyncUsersWorker, feed_file_path: #{feed_file_path}, file_path: #{file_path}"
    )

    insert_columns = [:encrypted_email, :hash_respid, :spanel, :created_at, :updated_at]
    discard_conflicts_on = [:encrypted_email]

    batch_manager = BatchManager.new(User, insert_columns, discard_conflicts_on,
                                     on_conflict_action = :nothing)

    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      next unless row[1].present?

      creation_time = Time.now
      batch_manager.add_to_batch(
        encrypted_email = row[1],
        hash_respid = row[2],
        spanel = row[3],
        creation_time,
        creation_time
      )
    end

    batch_manager.finish

    File.delete(feed_file_path)
    File.delete(file_path)

    logger.info("Finished SyncUsersWorker")
  end

  def logger
    environment = Rails.env

    @logger ||= Logger.new("log/sync_users_worker_#{environment}.log", 'monthly')
  end
end
