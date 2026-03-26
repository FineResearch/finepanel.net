class CreateWhatsappDeliveryResults < ActiveRecord::Migration[5.2]
  def change
    create_table :whatsapp_delivery_results do |t|

      t.string  :project_code
      t.string  :sample_number

      t.integer :panelist_id
      t.string  :panelist_email
      t.string  :whatsapp_number

      t.string  :status
      t.text    :error_message

      t.timestamps
    end

    add_index :whatsapp_delivery_results, :project_code
    add_index :whatsapp_delivery_results, :panelist_id
    add_index :whatsapp_delivery_results, :sample_number
    add_index :whatsapp_delivery_results, :status
  end
end
