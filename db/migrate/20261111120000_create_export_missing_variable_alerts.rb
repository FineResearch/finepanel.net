# frozen_string_literal: true

# Registro de las variables faltantes ya avisadas por proyecto (ver
# ExportMissingVariableAlert y ExportRelabeling::ProcessingAlertNotifier), para
# no mandar el mismo aviso en cada export diario del mismo proyecto. Tabla
# real (no Redis ni un archivo): tiene que sobrevivir a reinicios, migraciones
# de Redis y deploys.
class CreateExportMissingVariableAlerts < ActiveRecord::Migration[5.2]
  def change
    create_table :export_missing_variable_alerts do |t|
      t.string :project_id, null: false
      t.string :variable_name, null: false

      t.timestamps
    end

    add_index :export_missing_variable_alerts, %i[project_id variable_name],
              unique: true, name: 'index_export_missing_alerts_on_project_and_variable'
  end
end
