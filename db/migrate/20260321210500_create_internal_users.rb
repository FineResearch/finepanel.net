class CreateInternalUsers < ActiveRecord::Migration[5.2]
  def change
    create_table :internal_users do |t|
      t.string  :email, null: false
      t.string  :role, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :internal_users, :email, unique: true
    add_index :internal_users, :role
    add_index :internal_users, :active
  end
end
