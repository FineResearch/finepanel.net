# frozen_string_literal: true

require 'base64'

# Manda por mail los archivos ya re-etiquetados (.sav de SPSS, .xlsx de
# Excel) a los destinatarios extraidos del cuerpo del mail original de la
# Rule de Confirmit -- ver RelabelSpssExportWorker/RelabelExcelExportWorker.
class ExportDeliveryMailer < ApplicationMailer
  FROM = ENV.fetch('EXPORT_DELIVERY_FROM_EMAIL', 'export@export.finepanel.net')

  # relabeled: false cuando el pipeline de re-etiquetado (Excel o SPSS)
  # revento en algun punto core (no las mejoras opcionales, que ya
  # degradan solas -- ver RelabelExcelExportWorker#safely) y el worker
  # decidio mandar la base TAL CUAL LLEGO en vez de nada -- Diego: "lo mas
  # seguro seria que si algo falla se envie lo mismo que se recibio...
  # cubrimos el riesgo de que los datos se enviaron aunque el formato no
  # fuera perfecto". El asunto/cuerpo avisan la diferencia -- nunca hay que
  # decirle al destinatario que un archivo esta "corregido" cuando es el
  # original sin tocar.
  def relabeled_export_email(recipients, project_id, file_paths, relabeled: true)
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    personalization = generate_personalization(Array(recipients).join(','))
    personalization.subject = subject_for(project_id, relabeled)
    mail.add_personalization(personalization)

    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: body_for(project_id, file_paths, relabeled)))

    file_paths.each { |path| mail.add_attachment(build_attachment(path)) }

    send_email(mail)
  end

  private

  def subject_for(project_id, relabeled)
    relabeled ? "Base de datos re-etiquetada - #{project_id}" : "Base de datos - #{project_id}"
  end

  def body_for(project_id, file_paths, relabeled)
    attachments_list = file_paths.map { |path| File.basename(path) }.join(', ')
    intro = relabeled ? "Se adjunta la base de datos de #{project_id} con los labels corregidos." : (
      "No se pudo aplicar el re-etiquetado automatico de #{project_id} -- se adjunta la base de datos " \
      'tal cual se recibio, sin cambios de formato.'
    )

    "#{intro}\n\nArchivos incluidos: #{attachments_list}"
  end

  CONTENT_TYPES = {
    '.sav' => 'application/x-spss-sav',
    '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.zip' => 'application/zip'
  }.freeze

  def build_attachment(path)
    attachment = SendGrid::Attachment.new
    attachment.content = Base64.strict_encode64(File.read(path, mode: 'rb'))
    attachment.type = CONTENT_TYPES.fetch(File.extname(path), 'application/octet-stream')
    attachment.filename = File.basename(path)
    attachment.disposition = 'attachment'
    attachment
  end
end
