# frozen_string_literal: true

# Proveedor/equipo de campo para un pais -- reemplaza el array fijo
# TEAM_CONTACTS que antes vivia hardcodeado en el wizard (ver migracion
# CreateTeamContacts). paga_fine determina si entra en el script A7
# (incentivo equipo) generado para ese pais -- la generacion de links de
# equipos externos usa TODOS los proveedores del pais, sin filtrar por esto.
class TeamContact < ApplicationRecord
  validates :name, presence: true
  validates :pais1_rec_code, presence: true
end
