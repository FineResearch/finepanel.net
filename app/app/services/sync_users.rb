require 'csv'
require 'zip'

class SyncUsers
  class << self
    def import_users(file_path)
      CSV.foreach(file_path, col_sep: "\t", headers: true) do |row|
        next unless row[1].present?
        new_user = User.find_or_create_by(encrypted_email: row[1], hash_respid: row[2], spanel: row[3])
        puts new_user.encrypted_email + ' ' + new_user.errors.first[1] unless new_user.valid?
      end
    end
  end
end
