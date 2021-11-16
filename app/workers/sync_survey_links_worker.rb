# frozen_string_literal: true

require 'csv'
require 'batch_manager'

class SyncSurveyLinksWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path, texts)
    Rails.logger.info(
      "Starting SyncSurveyLinksWorker, feed_file_path: #{feed_file_path}, file_path: #{file_path}"
    )

    insert_columns = [:project_id, :resp_id, :spanel, :link, :created_at, :updated_at, :variables]
    discard_conflicts_on = [:project_id, :resp_id, :spanel, :link, :variables]

    batch_manager = BatchManager.new(SurveyLink, insert_columns, discard_conflicts_on)

    project_id = feed_file_path.match(/p\d+/).to_s

    active_users = User.with_active_app

    es_users = []
    por_users = []

    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      spanel = row[1].split('=').last
      link = row[1]

      next unless link.start_with?('http')

      creation_time = Time.now
      batch_manager.add_to_batch(
        project_id,
        resp_id = row[0],
        spanel,
        link,
        creation_time,
        creation_time,
        variables = row[2]
      )

      email = row[2]
      next unless email.present?

      encrypted_email = Digest::MD5.hexdigest(email)

      user = active_users.find_by(encrypted_email: encrypted_email)
      if user
        case user.language
        when 'es'
          es_users << email
        when 'por'
          por_users << email
        end
      end
    end

    batch_manager.finish

    PushNotificationsWorker.perform_async(es_users, texts['es'])
    PushNotificationsWorker.perform_async(por_users, texts['por'])

    File.delete(feed_file_path)
    File.delete(file_path)

    Rails.logger.info("Finished SyncSurveyLinksWorker")
  rescue => e
    Rails.logger.error { "SyncSurveyLinksWorker error: #{e.message[0, 300]} (#{e.class}" }
  end
end
