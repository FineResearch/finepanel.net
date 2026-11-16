# frozen_string_literal: true

# A quien le avisa Fine cuando un export no sale como corresponde (falta de
# permiso en Confirmit, el relabelling fallo, no se identifico el proyecto, el
# mail se descarto, etc.) -- Diego: "aviso a todo usuario con @fine-research.com
# [...] si no hay ninguno, usa por default" panel@fine-research.com.
#
# - Todas las direcciones @fine-research.com del envio (las del cuerpo del mail,
#   o las del Wizard si el Comment vino vacio), sin repetir. Nunca el cliente.
# - Si no hay ninguna (lista solo de clientes, mail sin destinatarios), la casilla
#   por default. Antes en ese caso no se avisaba a nadie y el fallo quedaba
#   silencioso -- justo el caso de las listas cargadas en el Wizard.
module ExportRelabeling
  class InternalAlertRecipients
    FINE_RESEARCH_DOMAIN = '@fine-research.com'
    DEFAULT = ENV.fetch('EXPORT_DISCARD_ALERT_EMAIL', 'panel@fine-research.com')

    def self.call(recipients)
      internal = Array(recipients).map { |email| email.to_s.strip }
                                  .select { |email| email.downcase.end_with?(FINE_RESEARCH_DOMAIN) }
                                  .uniq(&:downcase)
      internal.presence || [DEFAULT]
    end
  end
end
