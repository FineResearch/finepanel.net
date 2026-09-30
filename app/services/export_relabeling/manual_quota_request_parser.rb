# frozen_string_literal: true

# Parsea las secciones "Quotas:" y "Report:" que un PM puede agregar en el
# cuerpo del mail que dispara el export (abajo de los destinatarios, que ya
# se extraen aparte por MailerController#export_sync -- ver ese comentario,
# no hace falta ningun prefijo especial para los destinatarios, y esto
# tampoco lo necesita).
#
# Formato (ver conversacion con Diego, "el criterio es hacer algo simple
# que los PMs puedan implementar sin ambiguedades ni mucho trabajo"):
#
#   Quotas:
#   S0: 1=50; 2=30; 3=10; 4=5; 5=20
#   tipoficha: A=50 B=60
#   Report:
#   QuotaReg x tipoficha
#   tipoficha x qp0
#
# "Quotas:" -- una linea por variable, "variable: precode=meta" repetido.
# El separador entre pares es flexible a proposito (";", "," o simplemente
# espacio) -- un PM no deberia tener que ser prolijo con la puntuacion para
# que esto funcione. El precode es el que el PM lee en el schema/panel de
# Confirmit (no el label) -- ConfirmitVariableLookup#answer_label lo
# resuelve despues para mostrar y matchear el texto real si el export trae
# el label en vez del precode (ver QuotaProgressBuilder).
#
# "Report:" -- una linea por cruce, "variableA x variableB" (sin meta: ver
# ExportRelabeling::CrosstabBuilder, arma un crosstab de conteos, no
# controla contra ningun target).
#
# Cada seccion se corta en la primera linea que no matchea su propio
# patron (ademas de al encontrar la seccion siguiente) -- para no
# interpretar por error la firma del mail u otro texto libre como si fuera
# una linea de cuota/cruce.
module ExportRelabeling
  class ManualQuotaRequestParser
    QUOTAS_MARKER = /\AQuotas:?\z/i.freeze
    REPORT_MARKER = /\AReport:?\z/i.freeze
    QUOTA_LINE = /\A([^:]+):\s*(.+)\z/.freeze
    PAIR = /\A([^=\s]+)\s*=\s*(-?\d+)\z/.freeze
    CROSS_LINE = /\A(\S+)\s+x\s+(\S+)\z/i.freeze

    def self.call(body)
      new(body).call
    end

    def initialize(body)
      @lines = body.to_s.each_line.map(&:strip)
    end

    def call
      { quotas: parse_quotas, crosses: parse_crosses }
    end

    private

    def parse_quotas
      lines_after(QUOTAS_MARKER)
        .take_while { |line| line.match?(QUOTA_LINE) }
        .map { |line| parse_quota_line(line) }
        .compact
    end

    def parse_crosses
      lines_after(REPORT_MARKER)
        .take_while { |line| line.match?(CROSS_LINE) }
        .map { |line| parse_cross_line(line) }
    end

    def lines_after(marker)
      index = @lines.index { |line| line.match?(marker) }
      return [] unless index

      @lines[(index + 1)..-1].reject(&:blank?)
    end

    def parse_quota_line(line)
      match = QUOTA_LINE.match(line)
      variable = match[1].strip
      return nil if variable.blank?

      targets = match[2].gsub(/[;,]/, ' ').split(/\s+/).map { |pair| parse_pair(pair) }.compact
      return nil if targets.empty?

      { variable: variable, targets: targets }
    end

    def parse_pair(pair)
      match = PAIR.match(pair)
      return nil unless match

      { precode: match[1], meta: match[2].to_i }
    end

    def parse_cross_line(line)
      match = CROSS_LINE.match(line)
      { variable_a: match[1], variable_b: match[2] }
    end
  end
end
