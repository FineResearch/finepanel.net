class AddInboxFieldsToWhatsappConversations < ActiveRecord::Migration[5.2]
  def change
    add_column :whatsapp_conversations, :has_unread_messages, :boolean, null: false, default: false
    add_column :whatsapp_conversations, :window_expires_at, :datetime
    add_column :whatsapp_conversations, :resolved_at, :datetime
    add_reference :whatsapp_conversations, :resolved_by_user, foreign_key: { to_table: :internal_users }

    add_index :whatsapp_conversations, :has_unread_messages
    add_index :whatsapp_conversations, :window_expires_at
    add_index :whatsapp_conversations, :resolved_at
  end
end
