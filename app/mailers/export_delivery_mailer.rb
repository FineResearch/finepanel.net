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
  # includes_quotas/includes_report/includes_dictionary reflejan si ESTE
  # envio en particular trae esas hojas -- nunca un valor fijo por tipo de
  # export, para no prometer en el cuerpo algo que el archivo adjunto no
  # tiene. Desde que SPSS tambien puede traer una planilla de metadata
  # (Dictionary/Quotas/Report, ver RelabelSpssExportWorker), ninguno de
  # los 3 bullets esta atado a export_type -- antes includes_dictionary
  # existia, el bullet de Dictionary se mostraba siempre para Excel sin
  # chequear si esa hoja realmente se pudo armar.
  #
  # completed_quotas (ver ExportRelabeling::CompletedQuotas) -- array de
  # {quota:, field:, value:, target:, achieved:} para las cuotas que ya
  # alcanzaron o superaron la meta. Pedido de Diego: mostrarlas en el
  # cuerpo para que no haga falta abrir el Excel a buscarlas -- la seccion
  # entera se omite si no hay ninguna completa.
  def relabeled_export_email(
    recipients, project_id, file_paths, export_type:,
    relabeled: true, project_title: nil, includes_quotas: false, includes_report: false,
    includes_dictionary: false, interview_status_filter: nil, completed_quotas: [], delivery_zip_name: nil
  )
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    recipient_list = Array(recipients)
    personalization = generate_personalization(recipient_list.join(','))
    personalization.subject = subject_for(project_id, export_type, project_title)
    mail.add_personalization(personalization)

    body = body_for(project_reference(project_id, project_title), recipient_list, relabeled, includes_quotas, includes_report, includes_dictionary, interview_status_filter, completed_quotas)
    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: body))

    delivery_zip_path = build_delivery_zip(file_paths, project_id, delivery_zip_name)
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
    permission_denied: [
      'No se pudo hacer un procesamiento completo por falta de permisos, favor autorizar a la API de Confirmit.',
      'Confirmit respondio "Permission denied" al leer el schema del proyecto: el usuario de la API no tiene acceso a el.',
      'El export se entrego igual, pero sin traducir las cuotas ni el Report declarados en el mail (pueden figurar en 0),',
      'sin tipos en el Dictionary y sin deteccion de variables faltantes.',
      'Para corregirlo: dar acceso al usuario de la API al proyecto en Confirmit y volver a enviar el export.'
    ].join(' '),
    processing_error: 'Por algun motivo el archivo no pudo procesar integralmente, por favor chequear que el cliente reciba su export.',
    project_unidentified: 'No se pudo identificar el proyecto de Confirmit (el nombre del archivo no trae pXXXX y el cuerpo del mail no trae "Survey ID: pXXXX"). El export se entrego igual, pero sin consultar el schema: sin tipos en el Dictionary, sin traducir las cuotas y sin deteccion de variables faltantes. Revisar el texto de la Rule en Confirmit.'
  }.freeze

  def processing_alert_email(recipients, project_id, export_type:, alert_type:)
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    personalization = generate_personalization(Array(recipients).join(','))
    personalization.subject = "[ALERTA] #{project_id} - #{EXPORT_TYPE_LABELS.fetch(export_type)}"
    mail.add_personalization(personalization)

    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: alert_body(alert_type, project_id)))

    send_email(mail)
  end

  DISCARD_REASONS = {
    no_recipients: {
      label: 'no hay destinatarios: el mail no traia ninguna direccion y el proyecto no tiene direcciones cargadas en el Wizard',
      action: 'Cargar las direcciones del proyecto en el Wizard (Envio de exports) y dejar el Comment de la Rule vacio, ' \
              'o escribirlas en el Comment; despues volver a enviar el export.'
    },
    unrecognized_zip: {
      label: 'el zip no trae ningun .sps ni .xlsx (por ejemplo, un SPSS nativo .sav)',
      action: 'Cambiar el formato de export de la Rule a SPSS (sps/dat) o a Excel, y volver a enviar el export.'
    },
    processing_error: {
      label: 'error inesperado al recibir el mail',
      action: 'Volver a enviar el export; si se repite, revisar los logs de la Api.'
    }
  }.freeze

  # Alerta interna cuando MailerController#export_sync DESCARTA un mail sin
  # procesarlo (ver ExportRelabeling::DiscardedExportNotifier): el cliente NO
  # recibio ese export. Va a una casilla fija de Fine, nunca al cliente.
  def export_discarded_alert_email(recipients, reason:, filename: nil, sender: nil, project_id: nil, project_title: nil, entry_names: [])
    info = DISCARD_REASONS.fetch(reason)
    reference = project_id.presence || project_title.presence || filename.presence || 'sin identificar'

    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    personalization = generate_personalization(Array(recipients).join(','))
    personalization.subject = "[ALERTA] Export descartado - #{reference}"
    mail.add_personalization(personalization)

    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: discarded_body(info, reason, filename, sender, project_id, project_title, entry_names)))

    send_email(mail)
  end

  MAX_MISSING_VARIABLES_LISTED = 100

  # Alerta interna aparte (ver ExportRelabeling::MissingVariablesDetector):
  # preguntas del cuestionario que no llegaron en el export, para corregir el
  # Data Template del proyecto. Mismo canal que processing_alert_email: solo a
  # direcciones @fine-research.com, nunca al cliente.
  def missing_variables_alert_email(recipients, project_id, export_type:, variables:)
    mail = SendGrid::Mail.new
    mail.from = Email.new(email: FROM)

    personalization = generate_personalization(Array(recipients).join(','))
    personalization.subject = "[ALERTA] #{project_id} - #{EXPORT_TYPE_LABELS.fetch(export_type)} - faltan variables"
    mail.add_personalization(personalization)

    mail.add_content(SendGrid::Content.new(type: 'text/plain', value: missing_variables_body(variables)))

    send_email(mail)
  end

  private

  # El mensaje de cada tipo de alerta, con el proyecto al que se refiere (sin
  # eso habia que deducirlo del asunto).
  def alert_body(alert_type, project_id)
    lines = [ALERT_MESSAGES.fetch(alert_type)]
    lines << "Proyecto: #{project_id}" if project_id.present?
    lines.join("\n\n")
  end

  def discarded_body(info, _reason, filename, sender, project_id, project_title, entry_names)
    lines = ['El cliente NO recibio este export: se descarto sin procesarlo.', '']
    lines << "Motivo: #{info[:label]}"
    lines << "Archivo: #{filename.presence || '(sin nombre)'}"
    lines << "Proyecto: #{[project_id, project_title].select(&:present?).join(' - ').presence || 'no identificado'}"
    lines << "Remitente: #{sender.presence || '(desconocido)'}"
    lines << "Contenido del zip: #{Array(entry_names).join(', ')}" if Array(entry_names).any?
    lines << ''
    lines << "Que hacer: #{info[:action]}"
    lines.join("\n")
  end

  def missing_variables_body(variables)
    listed = variables.first(MAX_MISSING_VARIABLES_LISTED).map do |variable|
      variable[:title].present? && variable[:title] != variable[:name] ? "- #{variable[:name]} (#{variable[:title]})" : "- #{variable[:name]}"
    end
    extra = variables.length - listed.length

    lines = ["Faltan #{variables.length} variable(s) del cuestionario en el export:", *listed]
    lines << "... y #{extra} mas" if extra.positive?
    lines << ''
    lines << 'Se excluyen las anteriores a PRESENTATION, las posteriores a iradatos1 y las Hidden.'
    lines << 'Revisar el Data Template del proyecto. El cliente ya recibio su export.'
    lines.join("\n")
  end

  # Pedido de Diego: un solo adjunto en vez de uno por archivo (loops
  # incluidos) -- mas facil de guardar/reenviar para el cliente que varios
  # archivos sueltos. Se arma en un directorio temporal propio (no en
  # @work_dir del worker, que ya se borra en su propio "ensure" antes de
  # que este metodo pueda terminar) y se borra en el "ensure" de arriba
  # apenas se termina de leer para el adjunto.
  def build_delivery_zip(file_paths, project_id, delivery_zip_name)
    zip_dir = Dir.mktmpdir
    zip_path = File.join(zip_dir, "#{delivery_zip_basename(project_id, file_paths, delivery_zip_name)}.zip")

    Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
      file_paths.each { |path| zip.add(File.basename(path), path) }
    end

    zip_path
  end

  # Diego: el zip de entrega tiene que llamarse igual que el archivo
  # PRINCIPAL (nunca uno de loop, ej. fichas) -- delivery_zip_name ya
  # viene resuelto asi desde cada worker (ver
  # RelabelSpssExportWorker/RelabelExcelExportWorker#main_file_basename).
  #
  # Bug real (Diego): cuando el archivo de entrada no trae el patron
  # pXXXXX en el nombre Y tampoco se pudo resolver el "Survey ID:" del
  # cuerpo del mail (ver MailerController#export_sync), project_id llega
  # vacio -- "#{project_id}.zip" daba literalmente ".zip", un archivo SIN
  # nombre que varios dispositivos/clientes de mail no reconocen ni dejan
  # abrir. project_id/primer-archivo quedan como fallback para el caso
  # "el pipeline central revento, se manda el zip original tal cual" (ahi
  # no hay un archivo "principal" que distinguir de un loop).
  def delivery_zip_basename(project_id, file_paths, delivery_zip_name)
    return delivery_zip_name if delivery_zip_name.present?
    return project_id if project_id.present?

    first_file = file_paths.first
    return 'export' if first_file.blank?

    File.basename(first_file, File.extname(first_file)).presence || 'export'
  end

  # Cada parte se agrega solo si existe: antes, un project_id vacio dejaba un
  # asunto como "- Excel Export" (guion colgado), y el cuerpo decia "for ,".
  def subject_for(project_id, export_type, project_title)
    parts = []
    parts << "Project: #{project_title}" if project_title.present?
    parts << project_id if project_id.present?
    parts << EXPORT_TYPE_LABELS.fetch(export_type)
    parts.join(' - ')
  end

  # A que proyecto se refiere el cuerpo del mail: el ID si lo hay, si no el
  # titulo, si no una referencia generica -- nunca un hueco.
  def project_reference(project_id, project_title)
    project_id.presence || project_title.presence || 'your project'
  end

  def body_for(project_reference, recipient_list, relabeled, includes_quotas, includes_report, includes_dictionary, interview_status_filter, completed_quotas)
    <<~BODY
      This message is intended only for following recipients: #{recipient_list.join(', ')}

      Please find attached the latest data files for #{project_reference}, generated through our automated data delivery.
      The delivery includes:

      #{delivery_bullets(includes_quotas, includes_report, includes_dictionary, interview_status_filter)}

      The files reflect all interviews processed as of #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}.
      #{validation_note(relabeled)}
      #{completed_quotas_section(completed_quotas)}
      Best regards,
      Fine Research
    BODY
  end

  def delivery_bullets(includes_quotas, includes_report, includes_dictionary, interview_status_filter)
    bullets = ['* Latest survey data']
    bullets << '* Data dictionary, including variable names, labels and response codes' if includes_dictionary
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
