# frozen_string_literal: true

require 'csv'

class UpdateUsersWorker
  include Sidekiq::Worker
  include FilesHelper

  def perform(file_path)
    Rails.logger.info(
      "Starting UpdateUsersWorker, feed_file_path: #{file_path}"
    )

    csv_content = tab_separated_to_hash(file_path)

    csv_content.each do |row|
      next if row[:wapp_wapp].nil?

      whatsapp_number = row[:wapp_wapp].to_s.start_with?('+') ? row[:wapp_wapp] : "+#{row[:wapp_wapp]}"

      user = User.find_by_hash_respid(row[:respid])

      next unless user

      Rails.logger.info("Updating user #{row[:respid]}")

      user.update!(
        first_name: row[:name_poderia_confirmar_os_seus_nomes],
        last_name: row[:apellido_sobrenomes],
        professional_title: row[:titulo_titulo],
        formal_title: row[:titulo_titulo],
        whatsapp_number: whatsapp_number
      )
    end

    File.delete(file_path)

    Rails.logger.info('Finished UpdateUsersWorker')
  rescue StandardError => e
    Rails.logger.error { "UpdateUsersWorker error: #{e.message[0, 200]} (#{e.class}" }
  end
end
