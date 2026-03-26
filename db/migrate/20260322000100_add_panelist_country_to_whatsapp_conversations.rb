class AddPanelistCountryToWhatsappConversations < ActiveRecord::Migration[5.2]
  def change
    add_column :whatsapp_conversations, :panelist_country, :string
  end
end
