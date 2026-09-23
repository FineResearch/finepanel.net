# frozen_string_literal: true

# Reemplaza a active_app (que solo marcaba "en algun momento sincronizo via
# el feed de idioma de la app vieja", nunca se revertia a false) como la
# base real de "puede recibir push" -- 1 fila por dispositivo/token FCM
# registrado, en vez de 1 flag booleano por usuario. Un usuario puede tener
# mas de un dispositivo (telefono + tablet, o reinstalo y genero un token
# nuevo); el token unico es lo que identifica cada instalacion concreta
# ante Firebase.
class CreateDeviceTokens < ActiveRecord::Migration[5.2]
  def change
    create_table :device_tokens do |t|
      t.references :user, foreign_key: true, null: false
      t.string :token, null: false
      t.string :platform, null: false

      t.timestamps
    end

    add_index :device_tokens, :token, unique: true
  end
end
