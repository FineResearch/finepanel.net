# frozen_string_literal: true

require 'base64'
require 'zip'
require 'tmpdir'

# Manda por mail los archivos ya re-etiquetados (.sav de SPSS, .xlsx de
# Excel) a los destinatarios extraidos del cuerpo del mail original de la
# Rule de Confirmit -- ver RelabelSpssExportWorker/RelabelExcelExportWorker.
class ExportDeliveryMailer < ApplicationMailer
  # @finepanel.net (dominio raiz), no @export.finepanel.net -- ese subdominio
  # solo esta autenticado en SendGrid para RECIBIR (MX + Inbound Parse), no
  # para enviar (sin SPF/DKIM configurado ahi), asi que un envio saliente
  # desde esa direccion se perdia en silencio (confirmado: no aparecia ni en
  # el Activity Feed de SendGrid). El resto de los mailers de la app ya usan
  # el dominio raiz (ver comentarios@finepanel.net, auto-export@finepanel.net).
  FROM = ENV.fetch('EXPORT_DELIVERY_FROM_EMAIL', 'export@finepanel.net')

  # pXXXXX ya es el identificador que el cliente reconoce (viene de
  # Confirmit) -- "SPSS"/"Excel" distingue el tipo de archivo adjunto sin
  # tener que abrirlo. Pedido explicito de Diego, formato en ingles (el
  # destinatario final es el cliente, no un PM interno).
  EXPORT_TYPE_LABELS = { spss: 'SPSS Export', excel: 'Excel Export' }.freeze

  # relabeled: false cuando el pipeline de re-etiquetado (Excel o SPSS)
  # revento en algun punto core (no las mejoras opcionales, que ya
  # degradan solas -- ver RelabelExcelExportWorker#safely) y el worker
  # decidio mandar la base TAL CUAL LLEGO en vez de nada -- Diego: "lo mas
  # seguro seria que si algo falla se envie lo mismo que se recibio...
  # cubrimos el riesgo de que los datos se enviaron aunque el formato no
  # fuera perfecto". El asunto/cuerpo avisan la diferencia -- nunca hay que
  # decirle al destinatario que un archivo fue "automaticamente validado"
  # cuando esa validacion justamente fallo.
  #
  # project_title/interview_status_filter vienen de
  # ExportRelabeling::ConfirmitExportEmailParser, que los lee del propio
  # cuerpo del mail de la Rule de Confirmit (la unica fuente confirmada --
  # el SurveySchema no trae el titulo del proyecto). Ninguno de los dos
  # esta garantizado -- un PM probando a mano (sin pasar por una Rule real)
  # nunca los tiene, y el subject/cuerpo simplemente los omiten, nunca los
  # dejan a medias ("Project:  - pXXXXX - ...").
  #
  # includes_quotas/includes_report reflejan si ESTE envio en particular
  # trae esas hojas (Excel) -- nunca un valor fijo, para no prometer en el
  # cuerpo algo que el archivo adjunto no tiene.
  #
  # completed_quotas (ver ExportRelabeling::CompletedQuotas) -- array de
  # {quota:, field:, value:, target:, achieved:} para las cuotas que ya
  # alcanzaron o superaron la meta. Pedido de Diego: mostrarlas en el
  # cuerpo para que no haga falta abrir el Excel a buscarlas -- la seccion
  # entera se omite si no hay ninguna completa.
  def relabeled_export_email(
    recipients, project_id, file_paths, export_type:,
    relabeled: true, project_title: nil, includes_quotas: false, includes_report: false,
    interview_status_filter: nil, completed_quotas: []
  )
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    recipient_list = Array(recipients)
    personalization = generate_personalization(recipient_list.join(','))
    personalization.subject = subject_for(project_id, export_type, project_title)
    mail.add_personalization(personalization)

    body = body_for(project_id, recipient_list, export_type, relabeled, includes_quotas, includes_report, interview_status_filter, completed_quotas)
    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: body))

    delivery_zip_path = build_delivery_zip(file_paths, project_id)
    mail.add_attachment(build_attachment(delivery_zip_path))

    send_email(mail)
  ensure
    FileUtils.rm_rf(File.dirname(delivery_zip_path)) if delivery_zip_path
  end

  # Alerta interna (ver ExportRelabeling::ProcessingAlertNotifier) -- NUNCA
  # al cliente, solo a las direcciones @fine-research.com que ya estaban
  # en el envio original. 2 tipos, pedido explicito de Diego: falta de
  # permisos en la API de Confirmit, o cualquier otro error que impidio un
  # procesamiento integral.
  ALERT_MESSAGES = {
    permission_denied: 'No se pudo hacer un procesamiento completo por falta de permisos, favor autorizar a la API de Confirmit.',
    processing_error: 'Por algun motivo el archivo no pudo procesar integralmente, por favor chequear que el cliente reciba su export.'
  }.freeze

  def processing_alert_email(recipients, project_id, export_type:, alert_type:)
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    personalization = generate_personalization(Array(recipients).join(','))
    personalization.subject = "[ALERTA] #{project_id} - #{EXPORT_TYPE_LABELS.fetch(export_type)}"
    mail.add_personalization(personalization)

    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: ALERT_MESSAGES.fetch(alert_type)))

    send_email(mail)
  end

  private

  # Pedido de Diego: un solo adjunto en vez de uno por archivo (loops
  # incluidos) -- mas facil de guardar/reenviar para el cliente que varios
  # archivos sueltos. Se arma en un directorio temporal propio (no en
  # @work_dir del worker, que ya se borra en su propio "ensure" antes de
  # que este metodo pueda terminar) y se borra en el "ensure" de arriba
  # apenas se termina de leer para el adjunto.
  def build_delivery_zip(file_paths, project_id)
    zip_dir = Dir.mktmpdir
    zip_path = File.join(zip_dir, "#{project_id}.zip")

    Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
      file_paths.each { |path| zip.add(File.basename(path), path) }
    end

    zip_path
  end

  def subject_for(project_id, export_type, project_title)
    prefix = project_title.present? ? "Project: #{project_title} - " : ''
    "#{prefix}#{project_id} - #{EXPORT_TYPE_LABELS.fetch(export_type)}"
  end

  def body_for(project_id, recipient_list, export_type, relabeled, includes_quotas, includes_report, interview_status_filter, completed_quotas)
    <<~BODY
      This message is intended only for following recipients: #{recipient_list.join(', ')}

      Please find attached the latest data files for #{project_id}, generated through our automated data delivery.
      The delivery includes:

      #{delivery_bullets(export_type, includes_quotas, includes_report, interview_status_filter)}

      The files reflect all interviews processed as of #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}.
      #{validation_note(relabeled)}
      #{completed_quotas_section(completed_quotas)}
      Best regards,
      Fine Research
    BODY
  end

  def delivery_bullets(export_type, includes_quotas, includes_report, interview_status_filter)
    bullets = ['* Latest survey data']
    bullets << '* Data dictionary, including variable names, labels and response codes' if export_type == :excel
    bullets << '* Quota providing an updated view of fieldwork progress' if includes_quotas
    bullets << '* Key cross-tab status' if includes_report
    bullets << "* Interview Status Filter: #{interview_status_filter}" if interview_status_filter.present?
    bullets.join("\n")
  end

  def validation_note(relabeled)
    return 'As part of the process, data structure and variable labeling are automatically validated against the scripted questionnaire prior to delivery.' if relabeled

    'Note: automated validation against the scripted questionnaire could not be completed for this delivery -- ' \
      'the attached file reflects the data exactly as received, without relabeling.'
  end

  def completed_quotas_section(completed_quotas)
    return '' if completed_quotas.blank?

    lines = completed_quotas.map { |q| "#{q[:quota]} | #{q[:field]}: #{q[:value]} | Target: #{q[:target]} | Achieved: #{q[:achieved]}" }
    "\nCompleted Quotas:\n\n#{lines.join("\n")}\n"
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
