# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ConfirmitSchemaFetcher do
  let(:client) { instance_double(FinePanelSetup::ConfirmitSoapClient) }

  before do
    allow(FinePanelSetup::ConfirmitSoapClient).to receive(:new).and_return(client)
    allow(client).to receive(:log_on).and_return('key123')
  end

  it 'devuelve un ConfirmitVariableLookup cuando el schema se puede leer' do
    allow(client).to receive(:send).with(:get_raw_survey_schema, project_id: 'p123456', key: 'key123')
                                    .and_return(inner: '<Root></Root>')

    result = described_class.call('p123456')

    expect(result).to be_a(ExportRelabeling::ConfirmitVariableLookup)
  end

  # Confirmado contra un proyecto real: el faultstring literal de
  # Confirmit es "Server was unable to process request. ---> Permission
  # denied." -- esto hay que poder distinguirlo de cualquier otro error
  # (ver ExportRelabeling::ProcessingAlertNotifier).
  it 'levanta PermissionDeniedError cuando Confirmit rechaza por permisos' do
    allow(client).to receive(:send).with(:get_raw_survey_schema, project_id: 'p123456', key: 'key123')
                                    .and_raise(RuntimeError, 'No se pudo leer el SurveySchema: Server was unable to process request. ---> Permission denied.')

    expect { described_class.call('p123456') }.to raise_error(described_class::PermissionDeniedError)
  end

  it 'devuelve nil (sin levantar nada) para cualquier otro error' do
    allow(client).to receive(:send).with(:get_raw_survey_schema, project_id: 'p123456', key: 'key123')
                                    .and_raise(RuntimeError, 'timeout')

    expect(described_class.call('p123456')).to be_nil
  end
end
