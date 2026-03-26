class CreateWhatsappProjectPanelists < ActiveRecord::Migration[5.2]
  def change
    create_table :whatsapp_project_panelists do |t|
      t.references :user, foreign_key: true, null: true

      t.string :project_code, null: false
      t.string :panelist_id, null: false
      t.string :panelist_email
      t.string :sample_number

      t.string :whatsapp_number
      t.string :country
      t.string :support_email

      t.string :status, null: false, default: 'not_sent'
      t.boolean :agent_intervened, null: false, default: false
      t.string :confirmit_status

      t.text :original_survey_link
      t.text :original_cancel_link
      t.text :tracked_survey_link
      t.text :tracked_cancel_link

      t.datetime :message_sent_at
      t.datetime :clicked_at
      t.datetime :cancelled_at
      t.datetime :reply_received_at
      t.datetime :final_outcome_at

      t.timestamps
    end

    add_index :whatsapp_project_panelists, :project_code
    add_index :whatsapp_project_panelists, :panelist_id
    add_index :whatsapp_project_panelists, :sample_number
    add_index :whatsapp_project_panelists, :status
    add_index :whatsapp_project_panelists, :whatsapp_number
    add_index :whatsapp_project_panelists,
              [:project_code, :panelist_id],
              unique: true,
              name: 'idx_whatsapp_project_panelists_unique'
  end
end
