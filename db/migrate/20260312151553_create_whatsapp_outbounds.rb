class CreateWhatsappOutbounds < ActiveRecord::Migration[5.2]
  def change
    create_table :whatsapp_outbounds do |t|
      t.references :user, foreign_key: true
      t.string :whatsapp_number
      t.string :panelist_email
      t.string :subject
      t.string :project_code
      t.string :duration
      t.string :incentive
      t.string :sent_by
      t.text :survey_link
      t.text :main_survey_link
      t.string :template_name
      t.string :language
      t.string :status

      t.timestamps
    end

    add_index :whatsapp_outbounds, :whatsapp_number
    add_index :whatsapp_outbounds, :project_code
    add_index :whatsapp_outbounds, :created_at
  end
end
