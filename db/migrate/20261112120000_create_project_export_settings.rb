# frozen_string_literal: true

# Configuracion de envio del export de un proyecto, cargada en el Wizard (ver
# ProjectExportSetting): el mismo texto que antes se escribia en el Comment de la
# Rule de Confirmit (destinatarios, "Quotas:" y "Report:"), pero sin el limite de
# 255 caracteres de ese campo. Si el export llega con el cuerpo vacio, se usa
# esto (MailerController#export_sync). Tabla real, compartida entre usuarios y
# que sobrevive a los deploys.
class CreateProjectExportSettings < ActiveRecord::Migration[5.2]
  def change
    create_table :project_export_settings do |t|
      t.string :project_id, null: false
      t.text :body, null: false
      t.string :updated_by

      t.timestamps
    end

    add_index :project_export_settings, :project_id, unique: true
  end
end
