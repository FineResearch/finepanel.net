class CreateWhatsappConversations < ActiveRecord::Migration[5.2]
  def change
    create_table :whatsapp_conversations do |t|
      t.references :user, foreign_key: true, null: true

      t.string :panelist_id, null: false
      t.string :panelist_email
      t.string :whatsapp_number
      t.string :project_code, null: false
      t.string :sample_number
      t.string :support_email
      t.string :country

      t.string :status, null: false, default: 'open'

      t.datetime :last_inbound_at
      t.datetime :last_outbound_at
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :whatsapp_conversations, :whatsapp_number
    add_index :whatsapp_conversations, :project_code
    add_index :whatsapp_conversations, :status
    add_index :whatsapp_conversations,
              [:panelist_id, :project_code],
              unique: true,
              name: 'idx_whatsapp_conversations_panelist_project'
  end
end
