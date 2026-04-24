class AddWhatsappOptInFieldsToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :whatsapp_opt_in, :boolean, default: false, null: false
    add_column :users, :whatsapp_opt_in_at, :datetime
    add_column :users, :whatsapp_opt_in_source, :string
  end
end
