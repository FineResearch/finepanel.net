# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::DiscardedExportNotifier do
  it 'sin direcciones @fine-research.com en el mail, avisa a panel@fine-research.com (nunca al cliente)' do
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:export_discarded_alert_email).and_return(delivery)

    described_class.call(reason: :no_recipients, filename: 'export.zip', sender: 'mailer@us.confirmit.com', project_id: 'p123')

    expect(ExportDeliveryMailer).to have_received(:export_discarded_alert_email).with(
      ['panel@fine-research.com'], reason: :no_recipients, filename: 'export.zip', sender: 'mailer@us.confirmit.com',
      project_id: 'p123', project_title: nil, entry_names: []
    )
  end

  it 'si el mail traia direcciones @fine-research.com, avisa a todas ellas y no a las del cliente' do
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:export_discarded_alert_email).and_return(delivery)

    described_class.call(
      reason: :unrecognized_zip, filename: 'x.zip', recipients: ['cliente@iqvia.com', 'natalia@fine-research.com', 'dcasar@fine-research.com']
    )

    expect(ExportDeliveryMailer).to have_received(:export_discarded_alert_email).with(
      ['natalia@fine-research.com', 'dcasar@fine-research.com'], hash_including(reason: :unrecognized_zip)
    )
  end

  it 'si el envio falla, se loguea y no levanta (el controlador tiene que contestar 200)' do
    allow(ExportDeliveryMailer).to receive(:export_discarded_alert_email).and_raise(StandardError, 'sendgrid caido')

    expect { described_class.call(reason: :unrecognized_zip, filename: 'x.zip') }.not_to raise_error
  end
end
