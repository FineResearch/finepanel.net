# frozen_string_literal: true

# Los destinatarios de un export salen de las direcciones de email que aparecen
# en el texto (el Comment de la Rule de Confirmit, o lo cargado en el Wizard --
# ver ProjectExportSetting). Una sola definicion para que MailerController y el
# Wizard coincidan siempre en que direcciones cuentan.
module ExportRelabeling
  class ExportRecipients
    EMAIL_REGEX = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i.freeze
    # El disclaimer legal que Confirmit agrega al final del mail de la Rule
    # menciona esta direccion como contacto -- nunca un destinatario real.
    EXCLUDED = ['info@fine-research.com'].freeze

    def self.extract(text)
      text.to_s.scan(EMAIL_REGEX).uniq.reject { |email| EXCLUDED.include?(email.downcase) }
    end
  end
end
