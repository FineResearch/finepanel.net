class CreateWhatsappMessages < ActiveRecord::Migration[5.2]
  def change
    create_table :whatsapp_messages do |t|
      t.references :whatsapp_conversation, foreign_key: true, null: false

      t.string :direction, null: false
      t.string :message_type
      t.text :message_body

      t.string :message_id
      t.string :status

      t.string :from_phone_number
      t.string :from_phone_number_id
      t.string :to_phone_number

      t.string :template_name
      t.string :language

      t.text :payload_json

      t.datetime :sent_at
      t.datetime :received_at

      t.timestamps
    end

    add_index :whatsapp_messages, :direction
    add_index :whatsapp_messages, :message_id
    add_index :whatsapp_messages, :status
    add_index :whatsapp_messages, :received_at
    add_index :whatsapp_messages, :sent_at
  end
end
