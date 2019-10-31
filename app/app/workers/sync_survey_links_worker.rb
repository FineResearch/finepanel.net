# frozen_string_literal: true

require 'csv'

class SyncSurveyLinksWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path, texts)
    project_id = feed_file_path.match(/p\d+/).to_s

    active_users = User.where(active_app: true)

    es_users = []
    por_users = []

    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      spanel = row[1].split('=').last
      survey = SurveyLink.find_or_create_by(project_id: project_id, resp_id: row[0], link: row[1], spanel: spanel, variables: row[2])
      Rails.logger.info(survey.errors.first[1]) unless survey.valid?

      email = row[2]
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

    PushNotificationsWorker.perform_async(es_users, texts['es'])
    PushNotificationsWorker.perform_async(por_users, texts['por'])

    File.delete(feed_file_path)
    File.delete(file_path)
  end
end
