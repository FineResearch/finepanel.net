class AddConfirmitLinkPartsToWhatsappProjectPanelists < ActiveRecord::Migration[5.2]
  def change
    add_column :whatsapp_project_panelists, :survey_path, :string
    add_column :whatsapp_project_panelists, :survey_r, :string
    add_column :whatsapp_project_panelists, :survey_s, :string

    add_column :whatsapp_project_panelists, :cancel_path, :string
    add_column :whatsapp_project_panelists, :cancel_r, :string
    add_column :whatsapp_project_panelists, :cancel_s, :string

    add_index :whatsapp_project_panelists,
              [:survey_path, :survey_r, :survey_s],
              name: 'idx_whatsapp_project_panelists_survey_lookup'

    add_index :whatsapp_project_panelists,
              [:cancel_path, :cancel_r, :cancel_s],
              name: 'idx_whatsapp_project_panelists_cancel_lookup'
  end
end
