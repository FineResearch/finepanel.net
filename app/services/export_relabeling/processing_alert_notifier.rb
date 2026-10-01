# frozen_string_literal: true

# Avisa a Fine Research (nunca al cliente) cuando un export no se pudo
# procesar al 100% -- Diego: "vamos a generar alertas para no tener
# fallos silenciosos". Dos casos, separados a proposito:
#
# - permission_denied: el fetch del schema de Confirmit fallo
#   especificamente por falta de permisos (ver
#   ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError) --
#   el pipeline igual sigue y manda la base (cae a labels por texto, sin
#   cuotas automaticas), pero alguien tiene que autorizar la API.
# - processing_error: el pipeline central revento por cualquier OTRO
#   motivo (PSPP, un .xlsx corrupto, etc.) y el worker mando la base SIN
#   re-etiquetar como fallback -- ver RelabelSpssExportWorker/
#   RelabelExcelExportWorker.
#
# Los destinatarios de la alerta son SOLO las direcciones @fine-research.com
# que ya estaban en el cuerpo del mail original (nunca el cliente, nunca
# una lista aparte) -- si ninguna de las direcciones del envio es de ese
# dominio, no hay a quien avisar y no se manda nada.
module ExportRelabeling
  class ProcessingAlertNotifier
    FINE_RESEARCH_DOMAIN = '@fine-research.com'

    def self.call(recipients:, project_id:, export_type:, permission_denied: false, relabeled: true)
      new(
        recipients: recipients, project_id: project_id, export_type: export_type,
        permission_denied: permission_denied, relabeled: relabeled
      ).call
    end

    def initialize(recipients:, project_id:, export_type:, permission_denied:, relabeled:)
      @recipients = recipients
      @project_id = project_id
      @export_type = export_type
      @permission_denied = permission_denied
      @relabeled = relabeled
    end

    def call
      return unless alert_type

      targets = internal_recipients
      return if targets.empty?

      ExportDeliveryMailer.processing_alert_email(
        targets, @project_id, export_type: @export_type, alert_type: alert_type
      ).deliver_now
    end

    private

    def alert_type
      return :permission_denied if @permission_denied
      return :processing_error unless @relabeled

      nil
    end

    def internal_recipients
      Array(@recipients).select { |email| email.to_s.downcase.end_with?(FINE_RESEARCH_DOMAIN) }
    end
  end
end
