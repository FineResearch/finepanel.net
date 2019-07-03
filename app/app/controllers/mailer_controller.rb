# frozen_string_literal: true

require 'zip'

class MailerController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:sync]

  def sync
    file = params[:attachment1]
    sender = params[:from].scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)[0].strip

    if sender == ConfigurationReader.sender_email.strip || sender == ConfigurationReader.sender_email_alternative.strip
      file_root_path = Rails.root.join('tmp', 'feed_files')
      FileUtils.mkdir_p file_root_path unless File.directory?(file_root_path)

      file_path = File.join(file_root_path, file.original_filename)
      FileUtils.mv file.path, file_path

      feed_file_path = Zip::File.open(file_path) do |zip_file|
        entry = zip_file.glob('*.txt').first
        entry.extract(File.join(file_root_path, entry.name))

        File.join(file_root_path, entry.name)
      end

      if feed_file_path.include?('PanelistCredits')
        SyncCreditsAndPaymentsWorker.perform_async(feed_file_path, file_path)
      else
        if feed_file_path.include?(ConfigurationReader.project_id)
          SyncUsersWorker.perform_async(feed_file_path, file_path)
        else
          SyncSurveyLinksWorker.perform_async(feed_file_path, file_path)
        end
      end
    end

    head :ok
  end
end
