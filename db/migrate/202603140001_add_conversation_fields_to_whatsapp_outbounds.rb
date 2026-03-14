class AddConversationFieldsToWhatsappOutbounds < ActiveRecord::Migration[5.2]
  def change

    add_column :whatsapp_outbounds, :panelist_id, :integer
    add_column :whatsapp_outbounds, :sample_number, :string
    add_column :whatsapp_outbounds, :support_email, :string
    add_column :whatsapp_outbounds, :from_phone_number, :string
    add_column :whatsapp_outbounds, :from_phone_number_id, :string
    add_column :whatsapp_outbounds, :error_message, :text
    add_column :whatsapp_outbounds, :campaign_uuid, :string

  end
end
