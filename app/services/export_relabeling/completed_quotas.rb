# frozen_string_literal: true

# Extrae, de las filas ya armadas por QuotaProgressBuilder (hoja "Quotas"),
# las que estan COMPLETAS (conseguido >= meta, Pending <= 0) -- a pedido de
# Diego, para listarlas en el cuerpo del mail de entrega ("Completed
# Quotas"), asi el cliente/PM no tiene que abrir el Excel para ver que ya
# se cumplio una cuota.
#
# Las filas vienen con "Quota"/"Variable" vacios (nil) en todas menos la
# PRIMERA linea de cada grupo (ver QuotaProgressBuilder#dedupe_leading_columns)
# -- se arrastra el ultimo valor no vacio para poder nombrar cada fila
# completa igual. Las filas de encabezado (HEADER repetido por bloque) y
# las filas en blanco (separadoras entre bloques) se saltean.
module ExportRelabeling
  class CompletedQuotas
    def self.call(rows)
      new(rows).call
    end

    def initialize(rows)
      @rows = rows || []
    end

    def call
      @current_quota = nil
      @current_field = nil

      @rows.map { |row| process_row(row) }.compact
    end

    private

    def process_row(row)
      return if row == QuotaProgressBuilder::HEADER
      return if row.all?(&:nil?)

      quota_name, field, value, limit, achieved, pending = row
      @current_quota = quota_name if quota_name.present?
      @current_field = field if field.present?

      return unless achieved.is_a?(Integer) && pending.is_a?(Integer) && pending <= 0

      { quota: @current_quota, field: @current_field, value: value, target: limit, achieved: achieved }
    end
  end
end
