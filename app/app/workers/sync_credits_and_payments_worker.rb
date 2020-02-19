# frozen_string_literal: true

require 'csv'
require 'batch_manager'

class SyncCreditsAndPaymentsWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path)
    logger.info(
      "Starting SyncCreditsAndPaymentsWorker, feed_file_path: #{feed_file_path}, file_path: #{file_path}"
    )

    insert_columns = [:respid, :project_name, :credit, :concept, :email_date, :created_at, :updated_at]
    discard_conflicts_on = [:respid, :project_name, :credit, :concept, :email_date]

    batch_manager = BatchManager.new(Payment, insert_columns, discard_conflicts_on)

    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|

      next unless row[0].present? && row[4].present?
      next unless row[4].is_a?(Integer)

      section = row[2].split('.')[1] if row[2].present?
      project_name = section[1..-2] if section.present?
      date = row[6].split(' ') if row[6].present?
      email_date = Date.strptime(date[0], "%m/%d/%Y") if date.present?

      creation_time = Time.now
      batch_manager.add_to_batch(
        respid = row[0],
        project_name,
        credit = row[4],
        concept = row[5],
        email_date,
        creation_time,
        creation_time
      )
    end

    batch_manager.finish

    File.delete(feed_file_path)
    File.delete(file_path)

    logger.info("Finished SyncActiveUsersLanguageWorker")
  rescue => e
    logger.error { "SyncActiveUsersLanguageWorker error: #{e.backtrace}: #{e.message[0,200]} (#{e.class}" }
  end

  def logger
    environment = Rails.env

    @logger ||= Logger.new("log/sync_credits_and_payments_#{environment}.log", 'monthly')
  end
end
