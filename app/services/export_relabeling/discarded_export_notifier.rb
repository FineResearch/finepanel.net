# frozen_string_literal: true

# Avisa a Fine cuando MailerController#export_sync DESCARTA un mail sin
# procesarlo -- en esos casos no hay a quien avisar por los canales normales
# (las alertas internas salen a las direcciones @fine-research.com del propio
# mail, y aca justamente no se pudo leer ninguna o ni siquiera se proceso el
# envio), asi que el cliente se quedaba sin su base y nadie se enteraba (visto
# con un SPSS de FP-18928G cuyo cuerpo no traia destinatarios).
#
# Va a las direcciones @fine-research.com del mail (si las traia) y, si no hay
# ninguna, a panel@fine-research.com (ver InternalAlertRecipients), nunca al
# cliente. No se avisa por "remitente invalido": esa casilla recibe mails de
# cualquiera, y avisar cada uno la inundaria.
#
# Es de mejor esfuerzo: un fallo aca se loguea y nunca llega al controlador, que
# tiene que contestar 200 pase lo que pase.
module ExportRelabeling
  class DiscardedExportNotifier
    def self.call(reason:, filename: nil, sender: nil, project_id: nil, project_title: nil, entry_names: [], recipients: [])
      ExportDeliveryMailer.export_discarded_alert_email(
        InternalAlertRecipients.call(recipients), reason: reason, filename: filename, sender: sender,
        project_id: project_id, project_title: project_title, entry_names: entry_names
      ).deliver_now
    rescue StandardError => e
      Rails.logger.error("[DiscardedExportNotifier] no se pudo avisar del export descartado (#{reason}): #{e.class} #{e.message}")
    end
  end
end
