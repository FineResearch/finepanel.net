# frozen_string_literal: true

require 'csv'

class SyncSurveyLinksWorker
  include Sidekiq::Worker

  def perform(feed_file_path, file_path)
    project_id = feed_file_path.match(/p\d+/).to_s

    CSV.foreach(feed_file_path, col_sep: "\t", headers: true) do |row|
      spanel = row[1].split('=').last
      survey = SurveyLink.find_or_create_by(project_id: project_id, resp_id: row[0], link: row[1], spanel: spanel, variables: row[2])
      Rails.logger.info(survey.errors.first[1]) unless survey.valid?
    end

    File.delete(feed_file_path)
    File.delete(file_path)
  end
end
