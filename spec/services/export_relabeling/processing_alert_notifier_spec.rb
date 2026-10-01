# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ProcessingAlertNotifier do
  def stub_mailer
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:processing_alert_email).and_return(delivery)
    delivery
  end

  it 'manda alerta de permiso solo a las direcciones @fine-research.com del envio' do
    stub_mailer

    described_class.call(
      recipients: ['cliente@otraempresa.com', 'dcasar@fine-research.com', 'nati@fine-research.com'],
      project_id: 'p123456', export_type: :spss, permission_denied: true, relabeled: true
    )

    expect(ExportDeliveryMailer).to have_received(:processing_alert_email)
      .with(['dcasar@fine-research.com', 'nati@fine-research.com'], 'p123456', export_type: :spss, alert_type: :permission_denied)
  end

  it 'manda alerta de error de procesamiento cuando relabeled: false (y no es por permisos)' do
    stub_mailer

    described_class.call(
      recipients: ['dcasar@fine-research.com'], project_id: 'p123456', export_type: :excel,
      permission_denied: false, relabeled: false
    )

    expect(ExportDeliveryMailer).to have_received(:processing_alert_email)
      .with(['dcasar@fine-research.com'], 'p123456', export_type: :excel, alert_type: :processing_error)
  end

  it 'prioriza permission_denied sobre processing_error si ambos aplican' do
    stub_mailer

    described_class.call(
      recipients: ['dcasar@fine-research.com'], project_id: 'p123456', export_type: :spss,
      permission_denied: true, relabeled: false
    )

    expect(ExportDeliveryMailer).to have_received(:processing_alert_email)
      .with(['dcasar@fine-research.com'], 'p123456', export_type: :spss, alert_type: :permission_denied)
  end

  it 'no manda nada si todo salio bien (relabeled: true, sin problema de permisos)' do
    stub_mailer

    described_class.call(
      recipients: ['dcasar@fine-research.com'], project_id: 'p123456', export_type: :spss,
      permission_denied: false, relabeled: true
    )

    expect(ExportDeliveryMailer).not_to have_received(:processing_alert_email)
  end

  it 'no manda nada si ninguno de los destinatarios es @fine-research.com' do
    stub_mailer

    described_class.call(
      recipients: ['cliente@otraempresa.com'], project_id: 'p123456', export_type: :spss,
      permission_denied: true, relabeled: true
    )

    expect(ExportDeliveryMailer).not_to have_received(:processing_alert_email)
  end
end
