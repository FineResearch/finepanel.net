# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'zip'

RSpec.describe ExportDeliveryMailer do
  around do |example|
    original = ENV['DISABLE_EMAIL_DELIVERY']
    ENV['DISABLE_EMAIL_DELIVERY'] = 'true'
    example.run
    ENV['DISABLE_EMAIL_DELIVERY'] = original
  end

  def sent_json(mail)
    # mail.to_json en esta gema de SendGrid devuelve un Hash, no un string
    # JSON (a pesar del nombre) -- se lo vuelve a pasar por to_json/parse
    # para normalizarlo a claves string, sin asumir si el Hash original
    # viene con claves symbol o string.
    JSON.parse(mail.to_json.to_json)
  end

  # El mail manda un unico adjunto .zip (pedido de Diego: "se puede
  # zipear el o los archivo en un unico zip antes de enviarlo") -- este
  # helper decodifica ese adjunto y devuelve {nombre_de_entrada => contenido}
  # para poder revisar que archivos trae adentro y con que contenido.
  def zip_entries(attachment)
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'attachment.zip')
      File.write(zip_path, Base64.strict_decode64(attachment['content']), mode: 'wb')

      Zip::File.open(zip_path) do |zip|
        zip.each_with_object({}) { |entry, acc| acc[entry.name] = entry.get_input_stream.read }
      end
    end
  end

  it 'arma el mail con destinatarios, asunto por proyecto/tipo, y un adjunto por archivo' do
    Dir.mktmpdir do |dir|
      sav_path = File.join(dir, 'p123456_def.sav')
      File.write(sav_path, 'contenido sav de prueba')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com', 'b@cliente.com'], 'p123456', [sav_path], export_type: :spss)

      json = sent_json(sent_mail)
      personalization = json['personalizations'].first

      expect(personalization['to'].map { |t| t['email'] }).to contain_exactly('a@cliente.com', 'b@cliente.com')
      expect(personalization['subject']).to eq('p123456 - SPSS Export')
      expect(json['attachments'].length).to eq(1)
      expect(json['attachments'].first['filename']).to eq('p123456.zip')
      expect(json['attachments'].first['type']).to eq('application/zip')
      expect(zip_entries(json['attachments'].first)).to eq('p123456_def.sav' => 'contenido sav de prueba')

      body = json['content'].first['value']
      expect(body).to include('This message is intended only for following recipients: a@cliente.com, b@cliente.com')
      expect(body).to include('Please find attached the latest data files for p123456')
      expect(body).to include('* Latest survey data')
      expect(body).to include('automatically validated against the scripted questionnaire')
      expect(body).to include('Fine Research')
    end
  end

  it 'con includes_dictionary: true, agrega la linea de diccionario (sin importar el export_type -- SPSS tambien puede traer un Dictionary, ver RelabelSpssExportWorker)' do
    Dir.mktmpdir do |dir|
      xlsx_path = File.join(dir, 'p123456_def.xlsx')
      File.write(xlsx_path, 'contenido xlsx de prueba')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [xlsx_path], export_type: :excel, includes_dictionary: true)

      json = sent_json(sent_mail)
      expect(json['personalizations'].first['subject']).to eq('p123456 - Excel Export')
      expect(json['content'].first['value']).to include('* Data dictionary, including variable names, labels and response codes')
    end
  end

  it 'con export_type: :spss e includes_dictionary: true, tambien agrega la linea de diccionario' do
    Dir.mktmpdir do |dir|
      sav_path = File.join(dir, 'p123456_def.sav')
      File.write(sav_path, 'x')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [sav_path], export_type: :spss, includes_dictionary: true)

      expect(sent_json(sent_mail)['content'].first['value']).to include('* Data dictionary, including variable names, labels and response codes')
    end
  end

  it 'sin includes_dictionary, no agrega esa linea (ni para Excel)' do
    Dir.mktmpdir do |dir|
      xlsx_path = File.join(dir, 'p123456_def.xlsx')
      File.write(xlsx_path, 'x')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [xlsx_path], export_type: :excel)

      expect(sent_json(sent_mail)['content'].first['value']).not_to include('Data dictionary')
    end
  end

  it 'con project_title presente, lo antepone al subject' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'p123456_def.sav')
      File.write(path, 'x')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [path], export_type: :spss, project_title: 'Oncology Tracker')

      json = sent_json(sent_mail)
      expect(json['personalizations'].first['subject']).to eq('Project: Oncology Tracker - p123456 - SPSS Export')
    end
  end

  it 'con interview_status_filter presente, lo agrega como bullet (ausente si no viene)' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'p123456_def.sav')
      File.write(path, 'x')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(
        ['a@cliente.com'], 'p123456', [path], export_type: :spss, interview_status_filter: 'All(unfiltered)'
      )

      expect(sent_json(sent_mail)['content'].first['value']).to include('* Interview Status Filter: All(unfiltered)')
    end
  end

  it 'sin interview_status_filter, no agrega esa linea' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'p123456_def.sav')
      File.write(path, 'x')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [path], export_type: :spss)

      expect(sent_json(sent_mail)['content'].first['value']).not_to include('Interview Status Filter')
    end
  end

  it 'con includes_quotas/includes_report, agrega esas lineas (ninguna por defecto)' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'p123456_def.xlsx')
      File.write(path, 'x')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(
        ['a@cliente.com'], 'p123456', [path], export_type: :excel, includes_quotas: true, includes_report: true
      )

      body = sent_json(sent_mail)['content'].first['value']
      expect(body).to include('* Quota providing an updated view of fieldwork progress')
      expect(body).to include('* Key cross-tab status')
    end
  end

  it 'sin includes_quotas/includes_report, no promete esas hojas en el cuerpo' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'p123456_def.xlsx')
      File.write(path, 'x')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [path], export_type: :excel)

      body = sent_json(sent_mail)['content'].first['value']
      expect(body).not_to include('Quota providing an updated view')
      expect(body).not_to include('Key cross-tab status')
    end
  end

  # Diego: un export que NO se pudo relabellear va TAL COMO LLEGO de Confirmit -- el mismo zip, con su nombre, sin
  # envolverlo en otro zip -- para que se distinga a simple vista de un envio relabelled, y el cuerpo dice que no
  # esta relabelled y que consulten al PM por el documento relabelled.
  it 'con relabeled: false adjunta el zip ORIGINAL con su nombre (sin envolverlo) y avisa que no esta relabelled' do
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'FP-18915G - 3432521 - EXCEL_20261117.zip')
      File.write(zip_path, 'contenido zip de prueba')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [zip_path], export_type: :excel, relabeled: false)

      json = sent_json(sent_mail)
      body = json['content'].first['value']

      expect(json['personalizations'].first['subject']).to eq('p123456 - Excel Export')
      expect(body).to include('This is the traditional software default format. In this case the file is not relabelled.')
      expect(body).to include('Please check with the PM if you need the updated relabelled document.')
      expect(body).not_to include('are automatically validated against the scripted questionnaire prior')
      attachment = json['attachments'].first
      expect(attachment['filename']).to eq('FP-18915G - 3432521 - EXCEL_20261117.zip')
      expect(Base64.decode64(attachment['content'])).to eq('contenido zip de prueba')
    end
  end

  it 'el zip original NO se borra despues de enviarlo (es del worker, que ya lo limpia en su ensure)' do
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'original.zip')
      File.write(zip_path, 'contenido')
      allow_any_instance_of(described_class).to receive(:send_email)

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [zip_path], export_type: :excel, relabeled: false)

      expect(File.exist?(zip_path)).to be true
      expect(Dir.exist?(dir)).to be true
    end
  end

  it 'con relabeled: false pero un archivo que no es zip, lo empaqueta como siempre' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'datos.sav')
      File.write(path, 'contenido sav')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [path], export_type: :spss, relabeled: false)

      attachment = sent_json(sent_mail)['attachments'].first
      expect(attachment['filename']).to eq('p123456.zip')
      expect(zip_entries(attachment)).to eq('datos.sav' => 'contenido sav')
    end
  end

  # Pedido de Diego: "se puede zipear el o los archivo en un unico zip
  # antes de enviarlo" -- un solo adjunto, nunca uno por archivo, ni
  # siquiera cuando hay varios (ej. un loop de la encuesta como
  # "..._fichas.sav" ademas del archivo principal).
  it 'con mas de un archivo (ej. un loop), los zipea juntos en un unico adjunto' do
    Dir.mktmpdir do |dir|
      main_path = File.join(dir, 'p123456_def.sav')
      loop_path = File.join(dir, 'p123456_def_fichas.sav')
      File.write(main_path, 'contenido principal')
      File.write(loop_path, 'contenido del loop')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [main_path, loop_path], export_type: :spss)

      json = sent_json(sent_mail)
      expect(json['attachments'].length).to eq(1)
      expect(json['attachments'].first['filename']).to eq('p123456.zip')
      expect(zip_entries(json['attachments'].first)).to eq(
        'p123456_def.sav' => 'contenido principal',
        'p123456_def_fichas.sav' => 'contenido del loop'
      )
    end
  end

  # Bug real (Diego): cuando el archivo de entrada no trae el patron
  # pXXXXX en el nombre Y tampoco se pudo resolver el "Survey ID:" del
  # cuerpo del mail, project_id llega vacio -- "#{project_id}.zip" daba
  # literalmente ".zip", un archivo SIN nombre que varios dispositivos no
  # reconocian ni dejaban abrir.
  it 'con project_id vacio y sin delivery_zip_name, cae al nombre del primer archivo adjunto (nunca ".zip" sin nombre)' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'export_personalizado_relabeled.sav')
      File.write(path, 'contenido')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], nil, [path], export_type: :spss)

      json = sent_json(sent_mail)
      expect(json['attachments'].first['filename']).to eq('export_personalizado_relabeled.zip')
    end
  end

  # Diego: "el zip deberia aparecer con el mismo nombre del archivo
  # principal (no de loops)" -- delivery_zip_name ya viene resuelto asi
  # desde cada worker (ver RelabelSpssExportWorker/
  # RelabelExcelExportWorker#main_file_basename) y tiene prioridad sobre
  # project_id, que puede ser mas generico (compartido por el principal y
  # todos sus loops).
  it 'con delivery_zip_name presente, el zip final usa ese nombre en vez del project_id' do
    Dir.mktmpdir do |dir|
      main_path = File.join(dir, 'p123456_def_relabeled.sav')
      loop_path = File.join(dir, 'p123456_def_fichas_relabeled.sav')
      File.write(main_path, 'contenido principal')
      File.write(loop_path, 'contenido del loop')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(
        ['a@cliente.com'], 'p123456', [main_path, loop_path], export_type: :spss,
        delivery_zip_name: 'p123456_def_relabeled'
      )

      json = sent_json(sent_mail)
      expect(json['attachments'].first['filename']).to eq('p123456_def_relabeled.zip')
    end
  end

  describe 'Quotas' do
    it 'con quota_lines presentes, agrega la seccion (completas y abiertas, con pendiente) antes de "Best regards"' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'p123456_def.xlsx')
        File.write(path, 'x')

        sent_mail = nil
        allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

        quota_lines = [
          { quota: 'quota1', field: 'regiao', value: 'Sudeste', target: 50, achieved: 51, pending: -1 },
          { quota: 'quota1', field: 'regiao', value: "Região Norte ", target: 7, achieved: 5, pending: 2 },
          { quota: 'quota2', field: 's0', value: '1', target: 10, achieved: 10, pending: 0 }
        ]

        described_class.new.relabeled_export_email(
          ['a@cliente.com'], 'p123456', [path], export_type: :excel, quota_lines: quota_lines
        )

        body = sent_json(sent_mail)['content'].first['value']
        expect(body).to include("
Quotas:
")
        expect(body).not_to include('Completed Quotas')
        expect(body).to include('quota1 | regiao: Sudeste | Target: 50 | Achieved: 51 | Pending: -1')
        # la cuota abierta tambien sale, sin el espacio duro final del label
        expect(body).to include("quota1 | regiao: Região Norte | Target: 7 | Achieved: 5 | Pending: 2")
        expect(body).to include('quota2 | s0: 1 | Target: 10 | Achieved: 10 | Pending: 0')
        expect(body.index("
Quotas:
")).to be < body.index('Best regards')
      end
    end

    it 'sin quota_lines, no agrega la seccion' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'p123456_def.xlsx')
        File.write(path, 'x')

        sent_mail = nil
        allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

        described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [path], export_type: :excel)

        expect(sent_json(sent_mail)['content'].first['value']).not_to include("
Quotas:
")
      end
    end
  end

  describe '#processing_alert_email' do
    it 'arma una alerta interna de falta de permisos' do
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.processing_alert_email(['dcasar@fine-research.com'], 'p123456', export_type: :spss, alert_type: :permission_denied)

      json = sent_json(sent_mail)
      expect(json['personalizations'].first['to'].map { |t| t['email'] }).to eq(['dcasar@fine-research.com'])
      expect(json['personalizations'].first['subject']).to eq('[ALERTA] p123456 - SPSS Export')
      body = json['content'].first['value']
      expect(body).to include('favor autorizar a la API de Confirmit')
      expect(body).to include('Permission denied')
      expect(body).to include('dar acceso al usuario de la API al proyecto')
      expect(body).to include('Proyecto: p123456')
    end

    it 'arma una alerta interna de error de procesamiento' do
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.processing_alert_email(['dcasar@fine-research.com'], 'p123456', export_type: :excel, alert_type: :processing_error)

      body = sent_json(sent_mail)['content'].first['value']
      expect(body).to include('favor chequear que el cliente reciba su export')
    end
  end

  describe '#missing_variables_alert_email' do
    def deliver(variables)
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }
      described_class.new.missing_variables_alert_email(
        ['dcasar@fine-research.com'], 'p123456', export_type: :excel, variables: variables
      )
      sent_json(sent_mail)
    end

    it 'lista cada variable faltante con su titulo, solo a la direccion interna' do
      json = deliver([{ name: 'q5a', title: 'Q5A' }, { name: 'f12', title: nil }])

      expect(json['personalizations'].first['to'].map { |t| t['email'] }).to eq(['dcasar@fine-research.com'])
      expect(json['personalizations'].first['subject']).to eq('[ALERTA] p123456 - Excel Export - faltan variables')
      body = json['content'].first['value']
      expect(body).to include('Faltan 2 variable(s)')
      expect(body).to include('- q5a (Q5A)')
      expect(body).to include('- f12')
      expect(body).to include('Hidden')
      expect(body).to include('Data Template')
    end

    it 'no repite el titulo cuando es igual al nombre' do
      body = deliver([{ name: 'Q5A', title: 'Q5A' }])['content'].first['value']

      expect(body).to include("- Q5A
")
      expect(body).not_to include('Q5A (Q5A)')
    end

    it 'acota la lista y resume el resto' do
      variables = Array.new(130) { |index| { name: "v#{index}", title: nil } }

      body = deliver(variables)['content'].first['value']

      expect(body).to include('Faltan 130 variable(s)')
      expect(body).to include('- v99')
      expect(body).not_to include('- v100')
      expect(body).to include('... y 30 mas')
    end
  end

  # Visto en un envio real: sin project_id el asunto salio "- Excel Export" y
  # el cuerpo decia "latest data files for ,".
  describe 'sin project_id' do
    def delivery(project_id:, project_title:)
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'archivo.xlsx')
        File.write(path, 'x')
        described_class.new.relabeled_export_email(
          ['cliente@empresa.com'], project_id, [path], export_type: :excel, project_title: project_title
        )
      end
      sent_json(sent_mail)
    end

    it 'arma el asunto solo con el titulo y el tipo, sin guiones colgados' do
      json = delivery(project_id: nil, project_title: 'FP-18874N - Proyecto X')

      expect(json['personalizations'].first['subject']).to eq('Project: FP-18874N - Proyecto X - Excel Export')
    end

    it 'si no hay ni id ni titulo, el asunto es solo el tipo de export' do
      json = delivery(project_id: '', project_title: nil)

      expect(json['personalizations'].first['subject']).to eq('Excel Export')
    end

    it 'el cuerpo nombra el titulo cuando no hay id (no deja "for ,")' do
      body = delivery(project_id: nil, project_title: 'FP-18874N - Proyecto X')['content'].first['value']

      expect(body).to include('latest data files for FP-18874N - Proyecto X,')
      expect(body).not_to include('for ,')
    end

    it 'sin id ni titulo, el cuerpo usa una referencia generica' do
      body = delivery(project_id: nil, project_title: nil)['content'].first['value']

      expect(body).to include('latest data files for your project,')
    end

    it 'con id y titulo mantiene el asunto de siempre' do
      json = delivery(project_id: 'p123456', project_title: 'Mi proyecto')

      expect(json['personalizations'].first['subject']).to eq('Project: Mi proyecto - p123456 - Excel Export')
    end
  end

  describe '#processing_alert_email con proyecto no identificado' do
    it 'explica que el export salio degradado y que hay que revisar la Rule' do
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.processing_alert_email(['dcasar@fine-research.com'], 'FP-18874N', export_type: :excel, alert_type: :project_unidentified)

      body = sent_json(sent_mail)['content'].first['value']
      expect(body).to include('No se pudo identificar el proyecto de Confirmit')
      expect(body).to include('Survey ID')
    end
  end

  # Export retenido: el cliente NO lo recibe (ver ProcessingAlertNotifier.hold).
  describe '#processing_alert_email con el export retenido' do
    def deliver(alert_type, **extra)
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }
      described_class.new.processing_alert_email(
        ['dcasar@fine-research.com'], 'p862488762089', export_type: :excel, alert_type: alert_type, held: true,
        filename: 'FP-18915G - EXCEL_20261113.zip', intended_recipients: ['cliente@iqvia.com', 'dcasar@fine-research.com'], **extra
      )
      sent_json(sent_mail)
    end

    it 'avisa que el cliente NO recibio el export, con proyecto, archivo, error y a quienes iba' do
      json = deliver(:permission_denied, detail: 'Server was unable to process request. ---> Permission denied.')

      expect(json['personalizations'].first['subject']).to eq('[ALERTA - EXPORT NO ENVIADO] p862488762089 - Excel Export')
      body = json['content'].first['value']
      expect(body).to include('EXPORT NO ENVIADO: el cliente NO recibio este export')
      expect(body).to include('el usuario de la API no tiene acceso')
      expect(body).to include('dar acceso al usuario de la API al proyecto')
      expect(body).to include('Proyecto: p862488762089')
      expect(body).to include('Archivo: FP-18915G - EXCEL_20261113.zip')
      expect(body).to include('Error: Server was unable to process request. ---> Permission denied.')
      expect(body).to include('Destinatarios que no lo recibieron: cliente@iqvia.com, dcasar@fine-research.com')
    end

    it 'cada motivo trae su propia instruccion para destrabarlo' do
      expect(deliver(:schema_unavailable)['content'].first['value']).to include('volver a enviar el export')
      expect(deliver(:project_unidentified)['content'].first['value']).to include('Survey ID: pXXXX')
      expect(deliver(:processing_error)['content'].first['value']).to include('fallo el re-etiquetado')
    end

    it 'un desfasaje de datos explica la verificacion y cita el zip original guardado' do
      body = deliver(:data_mismatch, detail: '120 de 21251 celdas no coinciden', evidence: 'evidence/2026/11/16/p1/spss_ab_x.zip')['content'].first['value']

      expect(body).to include('NO coinciden con los del .dat original')
      expect(body).to include('Error: 120 de 21251 celdas no coinciden')
      expect(body).to include("Zip original guardado en s3://#{ExportRelabeling::PsppLambdaClient::BUCKET}/evidence/2026/11/16/p1/spss_ab_x.zip (se conserva unos 30 dias)")
    end

    it 'sin evidencia guardada no menciona ningun zip' do
      expect(deliver(:permission_denied)['content'].first['value']).not_to include('Zip original guardado')
    end

    it 'recorta un error larguisimo' do
      body = deliver(:processing_error, detail: "x#{'y' * 2000}")['content'].first['value']

      expect(body.lines.find { |line| line.start_with?('Error:') }.length).to be < 600
    end
  end

  # Export Excel que no se pudo relabellear y se entrego como llego de Confirmit (ver RelabelExcelExportWorker).
  describe '#processing_alert_email con el export enviado sin relabellear' do
    def deliver(alert_type, **extra)
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }
      described_class.new.processing_alert_email(
        ['dcasar@fine-research.com'], 'p899583054321', export_type: :excel, alert_type: alert_type, original_sent: true,
        filename: 'FP-18915G - EXCEL_20261117.zip', intended_recipients: ['cliente@iqvia.com', 'dcasar@fine-research.com'], **extra
      )
      sent_json(sent_mail)
    end

    it 'avisa que el cliente recibio el ORIGINAL sin relabellear, con motivo, archivo, error y a quienes les llego' do
      json = deliver(:permission_denied, detail: 'Permission denied')

      expect(json['personalizations'].first['subject']).to eq('[ALERTA - ENVIADO SIN RELABELLEAR] p899583054321 - Excel Export')
      body = json['content'].first['value']
      expect(body).to include('EXPORT ENVIADO SIN RELABELLEAR: el cliente recibio el archivo ORIGINAL de Confirmit')
      expect(body).not_to include('EXPORT NO ENVIADO')
      expect(body).to include('el usuario de la API no tiene acceso')
      expect(body).to include('Archivo: FP-18915G - EXCEL_20261117.zip')
      expect(body).to include('Error: Permission denied')
      expect(body).to include('Destinatarios que recibieron el archivo original: cliente@iqvia.com, dcasar@fine-research.com')
      expect(body).not_to include('Destinatarios que no lo recibieron')
    end
  end

  describe '#export_discarded_alert_email' do
    def deliver(**args)
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }
      described_class.new.export_discarded_alert_email(['panel@fine-research.com'], **args)
      sent_json(sent_mail)
    end

    it 'explica que el cliente no recibio el export, con motivo, archivo, proyecto y que hacer' do
      json = deliver(
        reason: :no_recipients, filename: 'FP-18928G - SPSS_20261111.zip', sender: 'mailer@us.confirmit.com',
        project_id: 'p588393362171', project_title: 'FP-18928G Hidradenite'
      )

      expect(json['personalizations'].first['to'].map { |t| t['email'] }).to eq(['panel@fine-research.com'])
      expect(json['personalizations'].first['subject']).to eq('[ALERTA] Export descartado - p588393362171')
      body = json['content'].first['value']
      expect(body).to include('El cliente NO recibio este export')
      expect(body).to include('no hay destinatarios')
      expect(body).to include('Archivo: FP-18928G - SPSS_20261111.zip')
      expect(body).to include('Proyecto: p588393362171 - FP-18928G Hidradenite')
      expect(body).to include('Que hacer: Cargar las direcciones del proyecto en el Wizard')
    end

    it 'para un zip sin .sps/.xlsx lista su contenido y sugiere cambiar el formato' do
      json = deliver(reason: :unrecognized_zip, filename: 'x.zip', entry_names: ['a_SPSS.sav', 'a_SPSS_l1.sav'])

      body = json['content'].first['value']
      expect(body).to include('Contenido del zip: a_SPSS.sav, a_SPSS_l1.sav')
      expect(body).to include('SPSS (sps/dat) o a Excel')
    end

    it 'sin proyecto identificado usa el nombre del archivo en el asunto' do
      json = deliver(reason: :processing_error, filename: 'raro.zip')

      expect(json['personalizations'].first['subject']).to eq('[ALERTA] Export descartado - raro.zip')
      expect(json['content'].first['value']).to include('Proyecto: no identificado')
    end
  end
end
