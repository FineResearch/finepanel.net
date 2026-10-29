# frozen_string_literal: true

# Antes estos valores eran tablas fijas en el codigo del wizard
# (SUGGESTED_VALUE_TABLE para el incentivo de panel por moneda/especialidad/
# duracion, TEAM_INCENTIVE_TABLE_BRASIL para el incentivo especial de
# equipos de Brasil) -- se convierten en tabla real para que se puedan
# editar desde una interfaz y queden compartidas entre todos los usuarios,
# sin perderse en cada deploy (mismo motivo que team_contacts). Decision del
# usuario, 2026-09-10.
#
# category: 'hard'/'other' (panel, especialidad dificil o no) o
# 'brasil_easy'/'brasil_hard_or_national' (incentivo equipo Brasil).
# currency: codigo tal cual lo usa el resto del wizard (ej. "R$", "MX$") --
# vacio ('') para las filas de Brasil, que no varian por moneda.
# max_minutes: limite superior de la banda de duracion (ver findLoiBand).
class CreateIncentiveRates < ActiveRecord::Migration[5.2]
  def up
    create_table :incentive_rates do |t|
      t.string :category, null: false
      t.integer :max_minutes, null: false
      t.string :currency, null: false, default: ''
      t.decimal :value, null: false, precision: 12, scale: 2

      t.timestamps
    end

    add_index :incentive_rates, %i[category max_minutes currency], unique: true, name: 'index_incentive_rates_on_key'

    panel_values = {
      'hard' => {
        10 => { 'R$' => 50, 'MX$' => 300, 'AR$' => 15_000, 'COL$' => 60_000, 'US$' => 30, 'S/' => 80, 'CL$' => 30_000, 'UY$' => 1200 },
        15 => { 'R$' => 110, 'MX$' => 400, 'AR$' => 20_000, 'COL$' => 100_000, 'US$' => 30, 'S/' => 80, 'CL$' => 30_000, 'UY$' => 1200 },
        25 => { 'R$' => 180, 'MX$' => 700, 'AR$' => 30_000, 'COL$' => 200_000, 'US$' => 70, 'S/' => 120, 'CL$' => 45_000, 'UY$' => 2800 },
        40 => { 'R$' => 200, 'MX$' => 900, 'AR$' => 40_000, 'COL$' => 240_000, 'US$' => 100, 'S/' => 140, 'CL$' => 70_000, 'UY$' => 4000 },
        60 => { 'R$' => 250, 'MX$' => 1200, 'AR$' => 50_000, 'COL$' => 300_000, 'US$' => 110, 'S/' => 180, 'CL$' => 90_000, 'UY$' => 4400 },
      },
      'other' => {
        10 => { 'R$' => 50, 'MX$' => 300, 'AR$' => 15_000, 'COL$' => 60_000, 'US$' => 30, 'S/' => 80, 'CL$' => 30_000, 'UY$' => 1200 },
        15 => { 'R$' => 110, 'MX$' => 400, 'AR$' => 20_000, 'COL$' => 100_000, 'US$' => 30, 'S/' => 80, 'CL$' => 30_000, 'UY$' => 1200 },
        25 => { 'R$' => 140, 'MX$' => 600, 'AR$' => 27_000, 'COL$' => 150_000, 'US$' => 50, 'S/' => 100, 'CL$' => 40_000, 'UY$' => 2000 },
        40 => { 'R$' => 160, 'MX$' => 700, 'AR$' => 35_000, 'COL$' => 175_000, 'US$' => 70, 'S/' => 120, 'CL$' => 60_000, 'UY$' => 2800 },
        60 => { 'R$' => 200, 'MX$' => 1000, 'AR$' => 45_000, 'COL$' => 240_000, 'US$' => 100, 'S/' => 150, 'CL$' => 75_000, 'UY$' => 4000 },
      },
    }

    brasil_values = {
      'brasil_easy' => { 15 => 170, 25 => 200, 40 => 280, 60 => 330 },
      'brasil_hard_or_national' => { 15 => 200, 25 => 250, 40 => 330, 60 => 380 },
    }

    now = Time.current
    rows = []

    panel_values.each do |category, bands|
      bands.each do |max_minutes, currencies|
        currencies.each do |currency, value|
          rows << { category: category, max_minutes: max_minutes, currency: currency, value: value, created_at: now, updated_at: now }
        end
      end
    end

    brasil_values.each do |category, bands|
      bands.each do |max_minutes, value|
        rows << { category: category, max_minutes: max_minutes, currency: '', value: value, created_at: now, updated_at: now }
      end
    end

    execute(<<~SQL)
      INSERT INTO incentive_rates (category, max_minutes, currency, value, created_at, updated_at)
      VALUES #{rows.map { |r| "('#{r[:category]}', #{r[:max_minutes]}, '#{r[:currency]}', #{r[:value]}, '#{r[:created_at].to_s(:db)}', '#{r[:updated_at].to_s(:db)}')" }.join(', ')}
    SQL
  end

  def down
    drop_table :incentive_rates
  end
end
