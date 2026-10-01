# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

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
      expect(json['attachments'].first['filename']).to eq('p123456_def.sav')
      expect(Base64.strict_decode64(json['attachments'].first['content'])).to eq('contenido sav de prueba')

      body = json['content'].first['value']
      expect(body).to include('This message is intended only for following recipients: a@cliente.com, b@cliente.com')
      expect(body).to include('Please find attached the latest data files for p123456')
      expect(body).to include('* Latest survey data')
      expect(body).to include('automatically validated against the scripted questionnaire')
      expect(body).to include('Fine Research')
    end
  end

  it 'con export_type: :excel, agrega la linea de diccionario (no la de SPSS)' do
    Dir.mktmpdir do |dir|
      xlsx_path = File.join(dir, 'p123456_def.xlsx')
      File.write(xlsx_path, 'contenido xlsx de prueba')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [xlsx_path], export_type: :excel)

      json = sent_json(sent_mail)
      expect(json['personalizations'].first['subject']).to eq('p123456 - Excel Export')
      expect(json['content'].first['value']).to include('* Data dictionary, including variable names, labels and response codes')
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
      expect(json['attachments'].first['filename']).to eq('input_export.zip')
    end
  end
end
