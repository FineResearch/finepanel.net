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
# - project_unidentified: el mail no trajo el ID del proyecto (ni en el nombre
#   del archivo ni como "Survey ID:" en el cuerpo) -- sin proyecto no hay
#   schema de Confirmit, asi que el export se entrega pero degradado (sin
#   tipos en el Dictionary, sin traducir cuotas, sin detectar faltantes) y sin
#   este aviso nadie se entera.
#
# Y otro aviso, aparte de los anteriores y no un fallo: las
# preguntas del cuestionario que faltan en el export (ver
# MissingVariablesDetector), para corregir el Data Template.
#
# Los destinatarios de la alerta son SOLO las direcciones @fine-research.com
# que ya estaban en el cuerpo del mail original (nunca el cliente, nunca
# una lista aparte) -- si ninguna de las direcciones del envio es de ese
# dominio, no hay a quien avisar y no se manda nada.
module ExportRelabeling
  class ProcessingAlertNotifier
    FINE_RESEARCH_DOMAIN = '@fine-research.com'

    def self.call(recipients:, project_id:, export_type:, permission_denied: false, relabeled: true, missing_variables: [], project_unidentified: false)
      new(
        recipients: recipients, project_id: project_id, export_type: export_type,
        permission_denied: permission_denied, relabeled: relabeled, missing_variables: missing_variables,
        project_unidentified: project_unidentified
      ).call
    end

    def initialize(recipients:, project_id:, export_type:, permission_denied:, relabeled:, missing_variables:, project_unidentified:)
      @recipients = recipients
      @project_id = project_id
      @export_type = export_type
      @permission_denied = permission_denied
      @relabeled = relabeled
      @missing_variables = Array(missing_variables)
      @project_unidentified = project_unidentified
    end

    def call
      targets = internal_recipients
      return if targets.empty?

      send_processing_alert(targets) if alert_type
      send_missing_variables_alert(targets) if @missing_variables.any?
    end

    private

    def send_processing_alert(targets)
      ExportDeliveryMailer.processing_alert_email(
        targets, @project_id, export_type: @export_type, alert_type: alert_type
      ).deliver_now
    end

    # Aparte de la alerta de procesamiento: no es un fallo del pipeline sino un
    # aviso para corregir el Data Template (ver MissingVariablesDetector). Si
    # ambas aplican salen 2 mails, cada uno con un solo tema.
    def send_missing_variables_alert(targets)
      ExportDeliveryMailer.missing_variables_alert_email(
        targets, @project_id, export_type: @export_type, variables: @missing_variables
      ).deliver_now
    end

    def alert_type
      return :permission_denied if @permission_denied
      return :processing_error unless @relabeled
      return :project_unidentified if @project_unidentified

      nil
    end

    def internal_recipients
      Array(@recipients).select { |email| email.to_s.downcase.end_with?(FINE_RESEARCH_DOMAIN) }
    end
  end
end
