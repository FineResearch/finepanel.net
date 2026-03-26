class CreateInvalidWhatsappNumbers < ActiveRecord::Migration[5.2]
  def change
    create_table :invalid_whatsapp_numbers do |t|

      t.integer :panelist_id
      t.string  :panelist_email
      t.string  :whatsapp_number

      t.string  :first_detected_project_code
      t.string  :last_detected_project_code

      t.datetime :first_detected_at
      t.datetime :last_detected_at

      t.integer :times_detected, default: 1

      t.text :last_error_message

      t.boolean :active, default: true

      t.timestamps
    end

    add_index :invalid_whatsapp_numbers, :panelist_id
    add_index :invalid_whatsapp_numbers, :whatsapp_number
  end
end
