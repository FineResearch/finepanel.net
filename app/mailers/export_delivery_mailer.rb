# frozen_string_literal: true

require 'base64'

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
  def relabeled_export_email(
    recipients, project_id, file_paths, export_type:,
    relabeled: true, project_title: nil, includes_quotas: false, includes_report: false,
    interview_status_filter: nil
  )
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    recipient_list = Array(recipients)
    personalization = generate_personalization(recipient_list.join(','))
    personalization.subject = subject_for(project_id, export_type, project_title)
    mail.add_personalization(personalization)

    body = body_for(project_id, recipient_list, export_type, relabeled, includes_quotas, includes_report, interview_status_filter)
    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: body))

    file_paths.each { |path| mail.add_attachment(build_attachment(path)) }

    send_email(mail)
  end

  private

  def subject_for(project_id, export_type, project_title)
    prefix = project_title.present? ? "Project: #{project_title} - " : ''
    "#{prefix}#{project_id} - #{EXPORT_TYPE_LABELS.fetch(export_type)}"
  end

  def body_for(project_id, recipient_list, export_type, relabeled, includes_quotas, includes_report, interview_status_filter)
    <<~BODY
      This message is intended only for following recipients: #{recipient_list.join(', ')}

      Please find attached the latest data files for #{project_id}, generated through our automated data delivery.
      The delivery includes:

      #{delivery_bullets(export_type, includes_quotas, includes_report, interview_status_filter)}

      The files reflect all interviews processed as of #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}.
      #{validation_note(relabeled)}

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
