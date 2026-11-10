# frozen_string_literal: true

require 'rails_helper'

# Caso real (p588393362171, 2026-11-10): Confirmit contesta con un Fault de
# "Permission denied" y el envelope arranca con ~500 caracteres de namespaces.
# El mensaje de error se cortaba a 300 caracteres y perdia el motivo, asi que
# el aviso interno de falta de permisos (ver
# ExportRelabeling::ConfirmitSchemaFetcher) nunca se disparaba.
RSpec.describe FinePanelSetup::ConfirmitSoapClient do
  let(:client) { described_class.new }

  let(:permission_denied_response) do
    namespaces = %w[soap xsi xsd wsa wsse wsu].map { |prefix| %(xmlns:#{prefix}="http://example.com/#{'namespace/' * 6}#{prefix}") }.join(' ')

    <<~XML
      <?xml version="1.0" encoding="utf-8"?><soap:Envelope #{namespaces}><soap:Body><soap:Fault><faultcode>soap:Server</faultcode><faultstring>Server was unable to process request. ---&gt; Permission denied.</faultstring><detail /></soap:Fault></soap:Body></soap:Envelope>
    XML
  end

  describe '#get_raw_survey_schema' do
    it 'incluye el motivo del Fault en el error aunque el envelope sea largo' do
      allow(client).to receive(:get_questionnaire).and_return(permission_denied_response)

      expect { client.send(:get_raw_survey_schema, project_id: 'p588393362171', key: 'k') }
        .to raise_error(RuntimeError, /p588393362171.*Permission denied/m)
    end

    it 'si no es un Fault, cae al principio de la respuesta' do
      allow(client).to receive(:get_questionnaire).and_return('<respuesta-rara>' + ('x' * 500) + '</respuesta-rara>')

      expect { client.send(:get_raw_survey_schema, project_id: 'p1', key: 'k') }
        .to raise_error(RuntimeError, /<respuesta-rara>x{200}/)
    end

    it 'devuelve el schema normalmente cuando la respuesta trae el resultado' do
      response = '<GetQuestionnaireResult Version="3"><Single><Name>q1</Name></Single></GetQuestionnaireResult>'
      allow(client).to receive(:get_questionnaire).and_return(response)

      result = client.send(:get_raw_survey_schema, project_id: 'p1', key: 'k')

      expect(result[:inner]).to include('<Name>q1</Name>')
    end
  end

  describe 'integracion con el aviso de permisos' do
    it 'ConfirmitSchemaFetcher reconoce el Permission denied real y lo levanta como PermissionDeniedError' do
      allow(described_class).to receive(:new).and_return(client)
      allow(client).to receive(:log_on).and_return('k')
      allow(client).to receive(:get_questionnaire).and_return(permission_denied_response)

      expect { ExportRelabeling::ConfirmitSchemaFetcher.call('p588393362171') }
        .to raise_error(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError)
    end
  end
end
