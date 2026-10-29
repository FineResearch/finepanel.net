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

  # Diego: "lo mas seguro seria que si algo falla se envie lo mismo que se
  # recibio" -- cuando el worker manda la base sin re-etiquetar (fallback),
  # el cuerpo tiene que avisarlo, nunca decir que la validacion automatica
  # paso cuando justamente fallo.
  it 'con relabeled: false, avisa en el cuerpo que no se pudo validar/re-etiquetar' do
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'input_export.zip')
      File.write(zip_path, 'contenido zip de prueba')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [zip_path], export_type: :spss, relabeled: false)

      json = sent_json(sent_mail)
      body = json['content'].first['value']

      expect(json['personalizations'].first['subject']).to eq('p123456 - SPSS Export')
      expect(body).to include('could not be completed for this delivery')
      expect(body).not_to include('are automatically validated against the scripted questionnaire prior')
      expect(json['attachments'].first['filename']).to eq('p123456.zip')
      expect(zip_entries(json['attachments'].first)).to eq('input_export.zip' => 'contenido zip de prueba')
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

  describe 'Completed Quotas' do
    it 'con completed_quotas presentes, agrega la seccion antes de "Best regards"' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'p123456_def.xlsx')
        File.write(path, 'x')

        sent_mail = nil
        allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

        completed_quotas = [
          { quota: 'quota1', field: 'regiao', value: 'Sudeste', target: 50, achieved: 51 },
          { quota: 'quota2', field: 's0', value: '1', target: 10, achieved: 10 }
        ]

        described_class.new.relabeled_export_email(
          ['a@cliente.com'], 'p123456', [path], export_type: :excel, completed_quotas: completed_quotas
        )

        body = sent_json(sent_mail)['content'].first['value']
        expect(body).to include('Completed Quotas:')
        expect(body).to include('quota1 | regiao: Sudeste | Target: 50 | Achieved: 51')
        expect(body).to include('quota2 | s0: 1 | Target: 10 | Achieved: 10')
        expect(body.index('Completed Quotas:')).to be < body.index('Best regards')
      end
    end

    it 'sin completed_quotas, no agrega la seccion' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'p123456_def.xlsx')
        File.write(path, 'x')

        sent_mail = nil
        allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

        described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [path], export_type: :excel)

        expect(sent_json(sent_mail)['content'].first['value']).not_to include('Completed Quotas')
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
      expect(json['content'].first['value']).to include('favor autorizar a la API de Confirmit')
    end

    it 'arma una alerta interna de error de procesamiento' do
      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.processing_alert_email(['dcasar@fine-research.com'], 'p123456', export_type: :excel, alert_type: :processing_error)

      body = sent_json(sent_mail)['content'].first['value']
      expect(body).to include('favor chequear que el cliente reciba su export')
    end
  end
end
