class AddInboxFieldsToWhatsappMessages < ActiveRecord::Migration[5.2]
  def change
    unless column_exists?(:whatsapp_messages, :source)
      add_column :whatsapp_messages, :source, :string, null: false, default: 'webhook'
      add_index :whatsapp_messages, :source
    end

    unless column_exists?(:whatsapp_messages, :internal_user_id)
      add_reference :whatsapp_messages, :internal_user, foreign_key: true
    end

    unless column_exists?(:whatsapp_messages, :template_name)
      add_column :whatsapp_messages, :template_name, :string
      add_index :whatsapp_messages, :template_name
    end

    unless column_exists?(:whatsapp_messages, :template_language)
      add_column :whatsapp_messages, :template_language, :string
    end
  end
end
