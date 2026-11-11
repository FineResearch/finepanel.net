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

    # Los avisos son de mejor esfuerzo: si algo falla aca (mail, base) se loguea y
    # listo. Un error que escapara de este metodo haria que Sidekiq reintente
    # TODO el trabajo del worker -- y con el, que el cliente reciba el export
    # duplicado.
    def call
      targets = internal_recipients
      return if targets.empty?

      send_processing_alert(targets) if alert_type
      send_missing_variables_alert(targets) if @missing_variables.any?
    rescue StandardError => e
      Rails.logger.error("[ProcessingAlertNotifier] no se pudo enviar el aviso interno de #{@project_id}: #{e.class} #{e.message}")
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
    #
    # Sale UNA vez por proyecto y variable (ver ExportMissingVariableAlert): los
    # exports de un proyecto se repiten todos los dias y el PM tarda en corregir
    # el Data Template, asi que sin esto el mismo aviso llegaria a diario. Si
    # mas adelante falta una variable distinta, se avisa solo de la nueva. Las
    # variables se marcan como avisadas DESPUES de mandar el mail: si el envio
    # falla, el aviso se reintenta en el proximo export en vez de perderse.
    def send_missing_variables_alert(targets)
      pending = not_yet_alerted
      return if pending.empty?

      ExportDeliveryMailer.missing_variables_alert_email(
        targets, @project_id, export_type: @export_type, variables: pending
      ).deliver_now

      remember_alerted(pending)
    end

    # Si la base falla, se avisa de todo (mejor un aviso repetido que ninguno).
    def not_yet_alerted
      names = ExportMissingVariableAlert.not_alerted(@project_id, @missing_variables.map { |variable| variable[:name] })
      @missing_variables.select { |variable| names.include?(variable[:name]) }
    rescue StandardError => e
      Rails.logger.error("[ProcessingAlertNotifier] no se pudo consultar los avisos previos de #{@project_id}: #{e.class} #{e.message}")
      @missing_variables
    end

    def remember_alerted(variables)
      ExportMissingVariableAlert.register(@project_id, variables.map { |variable| variable[:name] })
    rescue StandardError => e
      Rails.logger.error("[ProcessingAlertNotifier] no se pudo registrar el aviso de #{@project_id}: #{e.class} #{e.message}")
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
