# frozen_string_literal: true

require 'csv'

class UpdateUsersWorker
  include Sidekiq::Worker
  include FilesHelper

  BATCH_SIZE = 500

  def perform(file_path)
    Rails.logger.info(
      "Starting UpdateUsersWorker, feed_file_path: #{file_path}"
    )

    csv_content = tab_separated_to_hash(file_path)

    csv_content.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        next if row[:wapp_wapp].nil? || row[:email_o_seu_email_principal].nil?

        whatsapp_number = row[:wapp_wapp].to_s.start_with?('+') ? row[:wapp_wapp] : "+#{row[:wapp_wapp]}"
        email = row[:email_o_seu_email_principal]
        user = User.find_from_email(email)

        next unless user

        Rails.logger.info("Updating user #{email}")

        # 🔹 Base attributes (como estaba)
        attributes = {
          first_name: row[:name_poderia_confirmar_os_seus_nomes],
          last_name: row[:apellido_sobrenomes],
          professional_title: row[:titulo_titulo],
          formal_title: row[:titulo_titulo],
          whatsapp_number: whatsapp_number
        }

habilita_wapp =
  row[:habilitawapp].presence ||
  row[:habilitawapp_habilitawapp].presence

habilita_wapp = habilita_wapp.to_s.strip.downcase

if habilita_wapp.present? && %w[1 true yes sim si s y].include?(habilita_wapp)
          attributes[:whatsapp_opt_in] = true
          attributes[:whatsapp_opt_in_at] ||= Time.current
          attributes[:whatsapp_opt_in_source] = 'forsta_habilitawapp'

          Rails.logger.info(
            "Setting WhatsApp opt-in from Forsta for user #{email}"
          )
        end

        user.update!(attributes)
      end
    end

    File.delete(file_path)

    Rails.logger.info('Finished UpdateUsersWorker')
  rescue StandardError => e
    Rails.logger.error { "UpdateUsersWorker error: #{e.message[0, 200]} (#{e.class}" }
  end
end
