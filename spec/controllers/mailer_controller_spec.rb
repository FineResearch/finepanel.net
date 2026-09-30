# frozen_string_literal: true

require 'rails_helper'

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
end
