# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

# Cuenta corporativa fija para herramientas internas (ej. Fine Panel Setup).
# Solo la crea si todavia no existe -- re-correr el seed no pisa una
# contrasena ya cambiada por el usuario via el link de recuperacion.
internal_admin = InternalUser.find_or_initialize_by(email: 'panel@fine-research.com')
if internal_admin.new_record?
  internal_admin.role = 'admin'
  internal_admin.active = true
  internal_admin.password = ENV.fetch('FINE_PANEL_SETUP_INITIAL_PASSWORD', 'Fine1428%')
  internal_admin.save!
  puts "Creado InternalUser para panel@fine-research.com"
end
