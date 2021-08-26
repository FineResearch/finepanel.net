# frozen_string_literal: true

require 'csv'

desc 'Import Credits and Payments history from file'
task :import_credits_and_payments, [:file_path] => :environment do |_t, args|
  CSV.foreach(args[:file_path], encoding: 'UTF-8', col_sep: "\t", headers: true) do |row|
    next unless row[0].present?
    section = row[2].split('.')[1] if row[2].present?
    project_name = section[1..-2] if section.present?
    date = row[6].split(' ') if row[6].present?
    email_date = Date.strptime(date[0], "%m/%d/%Y") if date.present?

    payment = Payment.find_or_create_by(respid: row[0], project_name: project_name, credit: row[4], concept: row[5], email_date: email_date)
    Rails.logger.error(payment.errors.first[1]) unless payment.valid?
  end
end
