# frozen_string_literal: true

# Valor por default de incentivo (panel por moneda, o equipo especial de
# Brasil) -- reemplaza las tablas fijas SUGGESTED_VALUE_TABLE/
# TEAM_INCENTIVE_TABLE_BRASIL que antes vivian hardcodeadas en el wizard
# (ver migracion CreateIncentiveRates). Identificado por
# category+max_minutes+currency (currency vacio para las filas de Brasil,
# que no varian por moneda).
class IncentiveRate < ApplicationRecord
  validates :category, presence: true
  validates :max_minutes, presence: true
  validates :value, presence: true, numericality: true
end
