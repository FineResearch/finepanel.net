# frozen_string_literal: true

# Antes esto era un array fijo en el codigo del wizard (TEAM_CONTACTS,
# public/fine-panel-setup/index.html) -- se convierte en tabla real para que
# se pueda editar (agregar/borrar proveedores) desde una interfaz y quede
# compartido entre todos los usuarios, sin perderse en cada deploy (un
# archivo local o localStorage no sirven para esto -- se pisan/no se
# comparten). Decision del usuario, 2026-09-09.
#
# pais1_rec_code: mismo codigo que SCRIPT_COUNTRIES[].pais1Code en el
# wizard (ej. "1" = Brasil, "2" = Mexico) -- string, no integer, para
# matchear el formato que ya usa el resto del generador de script.
#
# paga_fine: ON/OFF nuevo (no existia en el array viejo) -- solo los
# proveedores con paga_fine=true entran en el script A7 (incentivo equipo)
# generado para el pais del proyecto; para la generacion de links de
# equipos externos entran TODOS los proveedores del pais, sin filtrar por
# esto. Los 17 proveedores existentes se migran con paga_fine=true (asi el
# A7 sigue incluyendolos igual que antes, sin cambiar el comportamiento
# actual con este cambio).
class CreateTeamContacts < ActiveRecord::Migration[5.2]
  def up
    create_table :team_contacts do |t|
      t.string :name, null: false
      t.string :pais1_rec_code, null: false
      t.boolean :paga_fine, null: false, default: true

      t.timestamps
    end

    add_index :team_contacts, [:pais1_rec_code, :name], unique: true

    existing_contacts = [
      ['LAURA', '3'], ['SABRINA', '3'],
      ['ELIANA', '1'], ['ROSE', '1'], ['TANIA', '1'], ['KELLY', '1'],
      ['GEOVANA', '1'], ['MAISA', '1'], ['TELMA', '1'], ['NADIA', '1'],
      ['NATALIA', '1'], ['MAGALY', '1'], ['MARIAROSA', '1'], ['BRIZU', '1'],
      ['SONIA', '5'],
      ['FLAVIA', '4'],
      ['PIVA', '2'],
    ]
    now = Time.current
    rows = existing_contacts.map do |name, pais1_rec_code|
      { name: name, pais1_rec_code: pais1_rec_code, paga_fine: true, created_at: now, updated_at: now }
    end
    execute(<<~SQL)
      INSERT INTO team_contacts (name, pais1_rec_code, paga_fine, created_at, updated_at)
      VALUES #{rows.map { |r| "('#{r[:name]}', '#{r[:pais1_rec_code]}', #{r[:paga_fine]}, '#{r[:created_at].to_s(:db)}', '#{r[:updated_at].to_s(:db)}')" }.join(', ')}
    SQL
  end

  def down
    drop_table :team_contacts
  end
end
