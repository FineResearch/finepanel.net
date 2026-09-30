# frozen_string_literal: true

class MailerController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:sync, :whatsapp_mailer, :update_user_mailer, :export_sync]

  EMAIL_REGEX = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i.freeze

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
        Rails.logger.info('Sync finished and SyncCreditsAndPaymentsWorker was enqueued')
      else
        if feed_file_path.include?(ConfigurationReader.project_id)
          if text_parser.match_users_language_file
            SyncActiveUsersLanguageWorker.perform_async(feed_file_path, file_path)
            Rails.logger.info('Sync finished and SyncActiveUsersLanguageWorker was enqueued')
          else
            SyncUsersWorker.perform_async(feed_file_path, file_path)
            Rails.logger.info('Sync finished and SyncUsersWorker was enqueued')
          end
        else
          SyncSurveyLinksWorker.perform_async(feed_file_path, file_path, texts_per_lang)
          Rails.logger.info('Sync finished and SyncSurveyLinksWorker was enqueued')
        end
      end
    end

    head :ok
  end

  def whatsapp_mailer
    file = params[:attachment1]
    sender = params[:from].scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)[0].strip rescue nil

    original_text = params[:text].to_s
    subject =
      params[:subject].presence ||
      params[:Subject].presence ||
      params['subject'].presence ||
      params['Subject'].presence

    Rails.logger.error("[whatsapp_mailer] params_keys=#{params.keys.inspect}")
    Rails.logger.error("[whatsapp_mailer] from=#{params[:from].inspect}")
    Rails.logger.error("[whatsapp_mailer] parsed_sender=#{sender.inspect}")
    Rails.logger.error("[whatsapp_mailer] valid_send=#{valid_send?(sender)}")
    Rails.logger.error("[whatsapp_mailer] subject=#{subject.inspect}")
    Rails.logger.error("[whatsapp_mailer] text=#{original_text.inspect}")

    begin
      safe_params = params.to_unsafe_h.except('attachment1')
      Rails.logger.error("[whatsapp_mailer] params_no_attachment=#{safe_params.inspect}")
    rescue StandardError => e
      Rails.logger.error("[whatsapp_mailer] params_no_attachment_error=#{e.class} - #{e.message}")
    end

    text = normalize_whatsapp_mailer_text(original_text)

    Rails.logger.error("[whatsapp_mailer] final_text=#{text.inspect}")
    Rails.logger.error("[whatsapp_mailer] attachment1_present=#{params[:attachment1].present?}")

    if valid_send?(sender)
      feed_file_path = file_path(file)
      Rails.logger.error("[whatsapp_mailer] feed_file_path=#{feed_file_path}")
      SendWhatsappMessagesWorker.perform_async(feed_file_path, text)
      Rails.logger.error('[whatsapp_mailer] worker enqueued')
    else
      Rails.logger.error('[whatsapp_mailer] invalid sender or sender missing')
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

  # Recibe los exports de Confirmit a re-etiquetar (SPSS/Excel) en la
  # casilla dedicada export@export.finepanel.net. El sub-tipo (SPSS vs
  # Excel) se distingue por contenido del zip, no por la casilla -- misma
  # logica de disambiguacion que ya usa #sync para sus propios sub-tipos,
  # pero agrupada aca para dejar lugar a sumar mas procesos de export
  # despues sin pedir una casilla nueva cada vez.
  #
  # Los destinatarios del reenvio salen del cuerpo del mail (una o mas
  # direcciones separadas por coma, sin ningun prefijo/keyword) -- si no
  # aparece ninguna, no se reenvia nada (nunca un fallback silencioso a una
  # lista hardcodeada, para no mandar el archivo a destinatarios
  # equivocados por una Rule mal configurada).
  def export_sync
    Rails.logger.info("Starting export_sync: #{params.inspect}")

    file = params[:attachment1]
    sender = params[:from].to_s.scan(EMAIL_REGEX)[0]&.strip

    unless valid_send?(sender)
      Rails.logger.error("[export_sync] remitente invalido: #{sender.inspect}")
      return head :ok
    end

    zip_path = save_uploaded_zip(file)
    project_id = file.original_filename[/p\d+/]
    recipients = params[:text].to_s.scan(EMAIL_REGEX).uniq

    if recipients.empty?
      Rails.logger.error("[export_sync] no se encontraron destinatarios en el cuerpo del mail, se descarta #{zip_path}")
      File.delete(zip_path)
      return head :ok
    end

    entry_names = Zip::File.open(zip_path) { |zip_file| zip_file.entries.map(&:name) }

    if entry_names.any? { |name| name.end_with?('.sps') }
      RelabelSpssExportWorker.perform_async(zip_path, project_id, recipients)
      Rails.logger.info('export_sync: RelabelSpssExportWorker enqueued')
    elsif entry_names.any? { |name| name.end_with?('.xlsx') }
      RelabelExcelExportWorker.perform_async(zip_path, project_id, recipients, params[:text].to_s)
      Rails.logger.info('export_sync: RelabelExcelExportWorker enqueued')
    else
      Rails.logger.error("[export_sync] zip sin .sps ni .xlsx reconocible, se descarta: #{entry_names}")
      File.delete(zip_path)
    end

    head :ok
  rescue StandardError => e
    Rails.logger.error("[MailerController#export_sync] #{e.class} - #{e.message}")
    head :ok
  end

  private

  def save_uploaded_zip(file)
    file_root_path = Rails.root.join('tmp', 'export_feed_files')
    FileUtils.mkdir_p(file_root_path) unless File.directory?(file_root_path)

    zip_path = File.join(file_root_path, file.original_filename)
    FileUtils.mv(file.path, zip_path)
    zip_path
  end

  def valid_send?(sender)
    [
      ConfigurationReader.sender_email.strip,
      ConfigurationReader.sender_email_alternative.strip
    ].include?(sender)
  end

  def normalize_whatsapp_mailer_text(text)
    normalized = text.to_s.dup

    # Remove the standard Forsta intro line
    normalized = normalized.sub(/\AAttached is the output of rule:.*?\r?\n/m, '')

    # Remove leading "Comment:" when the business payload starts there
    normalized = normalized.sub(/\AComment:\s*/i, '')

    # Normalize line endings
    normalized = normalized.gsub("\r\n", "\n").gsub("\r", "\n")

    normalized.strip
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
