class AddJtiToInternalUsers < ActiveRecord::Migration[5.2]
  class InternalUser < ActiveRecord::Base; end

  def up
    add_column :internal_users, :jti, :string
    InternalUser.reset_column_information
    InternalUser.find_each { |u| u.update_column(:jti, SecureRandom.uuid) }
    change_column_null :internal_users, :jti, false
    add_index :internal_users, :jti, unique: true
  end

  def down
    remove_index :internal_users, :jti
    remove_column :internal_users, :jti
  end
end
