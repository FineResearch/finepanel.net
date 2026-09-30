# frozen_string_literal: true

# Calcula las estadisticas por columna que pide el cliente para la hoja de
# diccionario de variables (media/min/max para numericas, cantidad de
# nulos, cantidad de ceros, % de nulos) -- opera directo sobre los valores
# ya presentes en el Excel que mando Confirmit, sin depender ni del .sps ni
# de la API (ver la conversacion: son 2 procesos separados, el Excel no
# tiene el .sps a mano).
#
# "Nulo" es blank? (nil o string vacio/solo espacios) -- no distingue entre
# "no correspondia" y "no contesto", esa distincion no esta disponible solo
# mirando el valor exportado.
module ExportRelabeling
  class ColumnStatistics
    def self.call(values)
      new(values).call
    end

    def initialize(values)
      @total = values.length
      @null_count = values.count { |v| v.nil? || v.to_s.strip.empty? }
      @numeric_values = values.reject { |v| v.nil? || v.to_s.strip.empty? }.map { |v| to_numeric(v) }.compact
    end

    def call
      {
        mean: @numeric_values.empty? ? nil : (@numeric_values.sum.to_f / @numeric_values.length).round(2),
        min: @numeric_values.min,
        max: @numeric_values.max,
        null_count: @null_count,
        zero_count: @numeric_values.count(&:zero?),
        null_percentage: @total.zero? ? nil : ((@null_count.to_f / @total) * 100).round(2)
      }
    end

    private

    def to_numeric(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
