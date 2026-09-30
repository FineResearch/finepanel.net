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

  it 'arma el mail con destinatarios, asunto por proyecto, y un adjunto por archivo' do
    Dir.mktmpdir do |dir|
      sav_path = File.join(dir, 'p123456_def.sav')
      File.write(sav_path, 'contenido sav de prueba')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com', 'b@cliente.com'], 'p123456', [sav_path])

      # mail.to_json en esta gema de SendGrid devuelve un Hash, no un string
      # JSON (a pesar del nombre) -- se lo vuelve a pasar por to_json/parse
      # para normalizarlo a claves string, sin asumir si el Hash original
      # viene con claves symbol o string.
      json = JSON.parse(sent_mail.to_json.to_json)
      personalization = json['personalizations'].first

      expect(personalization['to'].map { |t| t['email'] }).to contain_exactly('a@cliente.com', 'b@cliente.com')
      expect(personalization['subject']).to eq('Base de datos re-etiquetada - p123456')
      expect(json['attachments'].length).to eq(1)
      expect(json['attachments'].first['filename']).to eq('p123456_def.sav')
      expect(Base64.strict_decode64(json['attachments'].first['content'])).to eq('contenido sav de prueba')
    end
  end

  # Diego: "lo mas seguro seria que si algo falla se envie lo mismo que se
  # recibio" -- cuando el worker manda la base sin re-etiquetar (fallback),
  # el asunto/cuerpo tienen que avisarlo, nunca decir "corregido" sobre un
  # archivo que es el original sin tocar.
  it 'con relabeled: false, avisa en el asunto/cuerpo que se envio la base sin re-etiquetar' do
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'input_export.zip')
      File.write(zip_path, 'contenido zip de prueba')

      sent_mail = nil
      allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

      described_class.new.relabeled_export_email(['a@cliente.com'], 'p123456', [zip_path], relabeled: false)

      json = JSON.parse(sent_mail.to_json.to_json)
      personalization = json['personalizations'].first

      expect(personalization['subject']).to eq('Base de datos - p123456')
      expect(json['content'].first['value']).to include('No se pudo aplicar el re-etiquetado')
      expect(json['attachments'].first['filename']).to eq('input_export.zip')
    end
  end
end
