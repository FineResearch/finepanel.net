# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[5.2]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.string :encrypted_email, null: false, default: ""
      t.string :hash_respid, null: false, default: ""
      t.string :spanel, null: false, default: ""

      ## Rememberable
      t.datetime :remember_created_at
      t.timestamps null: false
    end

    add_index :users, :encrypted_email, unique: true
  end
end
