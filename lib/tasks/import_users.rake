# frozen_string_literal: true

require 'csv'

task :import_users, [:file_path] => :environment do |_t, args|
  CSV.foreach(args[:file_path], encoding: 'UTF-16', col_sep: "\t") do |row|
    new_user = User.find_or_create_by(encrypted_email: row[0], hash_respid: row[1], spanel: row[2])
    puts new_user.encrypted_email + ' ' + new_user.errors.first[1] unless new_user.valid?
  end
end
