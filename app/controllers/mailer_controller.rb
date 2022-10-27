# frozen_string_literal: true

class MailerController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:sync, :whatsapp_mailer, :update_user_mailer]

  def sync
   Rails.logger.info("Starting sync: #{params.inspect}")

    file = params[:attachment1]
    sender = params[:from].scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)[0].strip
    text = params[:text]

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

      text_parser = TextParser.new(text)
      texts_per_lang = text_parser.get_language_texts

      if feed_file_path.include?('PanelistCredits')
        SyncCreditsAndPaymentsWorker.perform_async(feed_file_path, file_path)
        Rails.logger.info("Sync finished and SyncCreditsAndPaymentsWorker was enqueued")
      else
        if feed_file_path.include?(ConfigurationReader.project_id)
          if text_parser.match_users_language_file
            SyncActiveUsersLanguageWorker.perform_async(feed_file_path, file_path)
            Rails.logger.info("Sync finished and SyncActiveUsersLanguageWorker was enqueued")
          else
            SyncUsersWorker.perform_async(feed_file_path, file_path)
            Rails.logger.info("Sync finished and SyncUsersWorker was enqueued")
          end
        else
          SyncSurveyLinksWorker.perform_async(feed_file_path, file_path, texts_per_lang)
          Rails.logger.info("Sync finished and SyncSurveyLinksWorker was enqueued")
        end
      end
    end

    head :ok
  end

  def whatsapp_mailer
    file = params[:attachment1]
    sender = params[:from].scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)[0].strip
    text = params[:text]

    if valid_send?(sender)
      feed_file_path = file_path(file)
      SendWhatsappMessagesWorker.perform_async(feed_file_path, text)
    end

    head :ok
  end

  def update_user_mailer
    file = params[:attachment1]
    sender = params[:from].scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)[0].strip

    if valid_send?(sender)
      feed_file_path = file_path(file)
      UpdateUsersWorker.perform_async(feed_file_path)
    end

    head :ok
  end

  private

  def valid_send?(sender)
    [
      ConfigurationReader.sender_email.strip,
      ConfigurationReader.sender_email_alternative.strip
    ].includes?(sender)
  end

  def file_path(file, file_format = 'txt')
    file_root_path = Rails.root.join('tmp', 'feed_files')
    FileUtils.mkdir_p file_root_path unless File.directory?(file_root_path)

    file_path = File.join(file_root_path, file.original_filename)
    FileUtils.mv file.path, file_path

    feed_file_path = Zip::File.open(file_path) do |zip_file|
      entry = zip_file.glob("*.#{file_format}").first
      entry.extract(File.join(file_root_path, entry.name))

      File.join(file_root_path, entry.name)
    end

    File.delete(file_path)
    feed_file_path
  end
end
