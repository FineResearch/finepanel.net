# frozen_string_literal: true

require 'csv'

class SyncCreditsAndPaymentsWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path)
    logger.info(
      "Starting SyncCreditsAndPaymentsWorker, feed_file_path: #{feed_file_path}, file_path: #{file_path}"
    )

    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|

      next unless row[0].present? && row[4].present?
      next unless row[4].to_i != 0

      section = row[2].split('.')[1] if row[2].present?
      project_name = section[1..-2] if section.present?
      date = row[6].split(' ') if row[6].present?
      email_date = Date.strptime(date[0], "%m/%d/%Y") if date.present?

      payment = Payment.find_or_create_by(respid: row[0], project_name: project_name, credit: row[4], concept: row[5], email_date: email_date)
      Rails.logger.error(payment.errors.first[1]) unless payment.valid?
    end


    File.delete(feed_file_path)
    File.delete(file_path)

    logger.info("Finished SyncActiveUsersLanguageWorker")
  end

  def logger
    environment = Rails.env

    @logger ||= Logger.new("log/sync_credits_and_payments_#{environment}.log", 'monthly')
  end
end
