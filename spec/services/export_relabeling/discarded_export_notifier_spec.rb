# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::DiscardedExportNotifier do
  it 'avisa a la casilla fija de Fine, nunca al cliente' do
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:export_discarded_alert_email).and_return(delivery)

    described_class.call(reason: :no_recipients, filename: 'export.zip', sender: 'mailer@us.confirmit.com', project_id: 'p123')

    expect(ExportDeliveryMailer).to have_received(:export_discarded_alert_email).with(
      ['panel@fine-research.com'], reason: :no_recipients, filename: 'export.zip', sender: 'mailer@us.confirmit.com',
      project_id: 'p123', project_title: nil, entry_names: []
    )
  end

  it 'si el envio falla, se loguea y no levanta (el controlador tiene que contestar 200)' do
    allow(ExportDeliveryMailer).to receive(:export_discarded_alert_email).and_raise(StandardError, 'sendgrid caido')

    expect { described_class.call(reason: :unrecognized_zip, filename: 'x.zip') }.not_to raise_error
  end
end
