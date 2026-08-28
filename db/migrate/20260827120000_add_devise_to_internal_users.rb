class AddDeviseToInternalUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :internal_users, :encrypted_password, :string, null: false, default: ''

    add_column :internal_users, :reset_password_token, :string
    add_column :internal_users, :reset_password_sent_at, :datetime
    add_index :internal_users, :reset_password_token, unique: true

    add_column :internal_users, :remember_created_at, :datetime
  end
end
