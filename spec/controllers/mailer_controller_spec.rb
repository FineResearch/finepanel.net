# frozen_string_literal: true

require 'rails_helper'
require 'zip'
require 'tmpdir'

RSpec.describe MailerController do
  # #valid_export_sender? es la unica validacion que Diego pidio abrir a
  # cualquier @fine-research.com (para poder probar/disparar exports sin
  # depender de panel@fine-research.com puntual) -- #valid_send? (usado por
  # #sync/#whatsapp_mailer/#update_user_mailer) queda intacto, ver el
  # comentario en el controller.
  describe '#valid_export_sender?' do
    subject(:valid_export_sender?) { controller.send(:valid_export_sender?, sender) }

    context 'con el remitente de Confirmit' do
      let(:sender) { 'mailer@us.confirmit.com' }

      it { is_expected.to be true }
    end

    context 'con cualquier direccion @fine-research.com' do
      let(:sender) { 'dcasar@fine-research.com' }

      it { is_expected.to be true }
    end

    context 'con @fine-research.com en mayusculas' do
      let(:sender) { 'Dcasar@Fine-Research.com' }

      it { is_expected.to be true }
    end

    context 'con un dominio no relacionado' do
      let(:sender) { 'alguien@gmail.com' }

      it { is_expected.to be false }
    end

    context 'con un dominio parecido pero distinto (no deberia matchear por substring)' do
      let(:sender) { 'alguien@notfine-research.com' }

      it { is_expected.to be false }
    end

    context 'sin remitente' do
      let(:sender) { nil }

      it { is_expected.to be false }
    end
  end

  # #valid_send? (las demas casillas del mailer) no se toco -- confirmamos
  # que sigue rechazando cualquier @fine-research.com que no sea
  # exactamente panel@fine-research.com, para no aflojarlo sin querer.
  describe '#valid_send? (sin cambios, usado por #sync/#whatsapp_mailer/#update_user_mailer)' do
    it 'sigue rechazando un @fine-research.com generico' do
      expect(controller.send(:valid_send?, 'dcasar@fine-research.com')).to be false
    end

    it 'sigue aceptando panel@fine-research.com' do
      expect(controller.send(:valid_send?, 'panel@fine-research.com')).to be true
    end
  end

  describe '#export_sync' do
    def build_zip(entry_name: 'data.sps', filename: 'p123456_def_dcasar_1.sps')
      dir = Dir.mktmpdir
      path = File.join(dir, filename)
      Zip::File.open(path, Zip::File::CREATE) { |zip| zip.get_output_stream(entry_name) { |f| f.write('contenido') } }
      path
    end

    def upload_for(path)
      Rack::Test::UploadedFile.new(path, 'application/zip')
    end

    # Visto en un envio real de Confirmit: el disclaimer legal del pie
    # menciona info@fine-research.com, y el scan de destinatarios sobre
    # TODO el cuerpo la agarraba como si fuera un destinatario real.
    it 'excluye info@fine-research.com (disclaimer de Confirmit) de los destinatarios, y pasa project_title/interview_status_filter al worker' do
      body = <<~BODY
        Survey ID: p123456
        Survey Name: "FP-18358N - 3418357_ATU CPNPC Early Stages Imfinzi"
        Interview Status Filter: All(unfiltered)
        Comment: dcasar@fine-research.com

        The information contained in this email message may be privileged. Contact info@fine-research.com.
      BODY

      expect(RelabelSpssExportWorker).to receive(:perform_async) do |_zip_path, project_id, recipients, email_body, project_title, interview_status_filter|
        expect(project_id).to eq('p123456')
        expect(recipients).to eq(['dcasar@fine-research.com'])
        expect(email_body).to eq(body)
        expect(project_title).to eq('FP-18358N - 3418357_ATU CPNPC Early Stages Imfinzi')
        expect(interview_status_filter).to eq('All(unfiltered)')
      end

      post :export_sync, params: { attachment1: upload_for(build_zip), from: 'mailer@us.confirmit.com', text: body }
    end

    # Diego: "a veces los PMs pueden customizar el nombre del proyecto
    # pXXXXX cuando el envio es directo de Confirmit... en esos casos
    # donde el pXXXX falte, es tomar el numero de la nota que viene en el
    # mensaje" -- visto de verdad: un envio real llego con el project_id
    # vacio porque el filename no tenia el patron esperado.
    it 'si el nombre del archivo no trae el project_id, cae al "Survey ID:" del cuerpo del mail' do
      body = <<~BODY
        Survey ID: p833174000229
        Comment: dcasar@fine-research.com
      BODY

      expect(RelabelSpssExportWorker).to receive(:perform_async) do |_zip_path, project_id, *_rest|
        expect(project_id).to eq('p833174000229')
      end

      post :export_sync, params: {
        attachment1: upload_for(build_zip(filename: 'export_personalizado.sps')),
        from: 'mailer@us.confirmit.com', text: body
      }
    end

    # Antes de este fix, si algo revienta DESPUES de guardar el zip (ej. el
    # adjunto no es un zip valido) el archivo quedaba huerfano para siempre
    # en tmp/feed_files/export (EFS compartido).
    it 'si algo revienta despues de guardar el zip, igual lo borra (no lo deja huerfano)' do
      upload = upload_for(build_zip)
      allow(Zip::File).to receive(:open).and_raise(Zip::Error, 'adjunto no es un zip valido')

      saved_path = Rails.root.join('tmp', 'feed_files', 'export', 'p123456_def_dcasar_1.sps')

      post :export_sync, params: { attachment1: upload, from: 'mailer@us.confirmit.com', text: 'dcasar@fine-research.com' }

      expect(File.exist?(saved_path)).to be false
    end
  end
end
