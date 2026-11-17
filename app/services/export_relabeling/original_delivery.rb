# frozen_string_literal: true

# Cuando un export (Excel o SPSS) no se puede relabellear -- sin permiso en Confirmit, schema ilegible,
# proyecto sin ID, fallo del proceso, o datos del .sav que no coinciden con el .dat (ver SavVerifier) --
# se entrega IGUAL el zip ORIGINAL de Confirmit, sin tocarlo y con su mismo nombre (no "..._relabeled"),
# con un mensaje al cliente que dice que no esta relabelled (ver ExportDeliveryMailer#validation_note), y
# ademas se avisa a Fine con el motivo y el error.
#
# Diego: retener el export arriesgaba perder eventos de farmacovigilancia; el cliente tiene que recibir
# sus datos siempre, y que el envio se distinga claramente de uno relabelled. El original trae los datos
# tal como los exporto Confirmit, asi que tambien es seguro cuando el que esta en duda es NUESTRO .sav.
#
# Lo incluyen RelabelSpssExportWorker y RelabelExcelExportWorker; cada uno define EXPORT_TYPE y
# @evidence_key (ver EvidenceStore).
module ExportRelabeling
  module OriginalDelivery
    private

    # Primero se entrega: es lo que no puede fallar en silencio (si el mail al cliente falla, la
    # excepcion sube y Sidekiq reintenta); el aviso interno es de mejor esfuerzo.
    def deliver_original(zip_path, recipients, project_id, project_title, interview_status_filter, alert_project, alert_type, detail)
      export_type = self.class::EXPORT_TYPE
      Rails.logger.error("[#{self.class.name}] export SIN relabellear (#{alert_type}) de #{alert_project.presence || 'proyecto no identificado'}: #{detail}")
      ExportDeliveryMailer.relabeled_export_email(
        recipients, project_id, [zip_path], export_type: export_type, relabeled: false,
        project_title: project_title, interview_status_filter: interview_status_filter
      ).deliver_now
      logger.info("[#{self.class.name}] export entregado SIN relabellear: proyecto=#{alert_project.presence || 'no identificado'} archivo=#{File.basename(zip_path.to_s)} destinatarios=#{Array(recipients).length}")

      ProcessingAlertNotifier.original_sent(
        recipients: recipients, project_id: alert_project, export_type: export_type, alert_type: alert_type,
        detail: detail, filename: File.basename(zip_path.to_s), evidence: @evidence_key
      )
    end
  end
end
