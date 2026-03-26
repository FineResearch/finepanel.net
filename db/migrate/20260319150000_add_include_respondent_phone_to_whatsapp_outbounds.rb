class AddIncludeRespondentPhoneToWhatsappOutbounds < ActiveRecord::Migration[5.2]
  def change
    add_column :whatsapp_outbounds, :include_respondent_phone, :boolean, default: false, null: false
  end
end
