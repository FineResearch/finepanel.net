# frozen_string_literal: true

require 'zip'

class MailerController < ApplicationController
   skip_before_action :verify_authenticity_token, only: [:sync]

  def sync
    file = params[:attachment1]
    file_root_path  = Rails.root.join('tmp', 'feed_files')
    file_path = File.join(file_root_path, file.original_filename)
    FileUtils.mv file.path, file_path

    feed_file_path = Zip::File.open(file_path) do |zip_file|
      entry = zip_file.glob('*.txt').first
      entry.extract(File.join(file_root_path, entry.name))

      File.join(file_root_path, entry.name)
    end

    if feed_file_path.include?(ConfigurationReader.project_id)
      SyncUsers.import_users(feed_file_path)
    else
      SyncSurveyLinks.import_survey_links(feed_file_path)
    end

    File.delete(feed_file_path)
    File.delete(file_path)

    head :ok
  end
end
