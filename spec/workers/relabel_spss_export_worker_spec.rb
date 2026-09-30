# frozen_string_literal: true

require 'rails_helper'
require 'zip'
require 'tmpdir'

RSpec.describe RelabelSpssExportWorker do
  # Sin esto, cada test intentaria pegarle a la API real de Confirmit --
  # se prueba aparte, fuera de la suite (ver ConfirmitVariableLookup y
  # ConfirmitSchemaFetcher). Devolver nil reproduce el comportamiento sin
  # API (fallback 100% a LabelParser), que es lo que validan estos tests.
  before { allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(nil) }

  let(:sps_content) do
    <<~SPS
      FILE HANDLE F1
       /NAME = 'c:\\temp\\data.asc'
       /LRECL=10.
      DATA LIST
       FIXED FILE = F1
       RECORDS=1
      /1
       Q1 1-2
      .
      VARIABLE LABELS
       Q1 'Pergunta (F1 - Texto de la pregunta)'
      .
      LIST.
    SPS
  end

  let(:zip_path) do
    dir = Dir.mktmpdir
    path = File.join(dir, 'test_export.zip')
    Zip::File.open(path, Zip::File::CREATE) do |zip|
      zip.get_output_stream('data.sps') { |f| f.write(sps_content) }
      zip.get_output_stream('data.asc') { |f| f.write("1 \n") }
    end
    path
  end

  # El compile real corre en una Lambda aparte (ver
  # ExportRelabeling::PsppLambdaClient) -- se stubea esa llamada en vez de
  # invocar PSPP/S3/Lambda de verdad. La validacion de que PSPP entiende la
  # sintaxis (y de que la Lambda compila un .sav real) ya se hizo a mano
  # contra un archivo real de Confirmit, fuera de la suite.
  def stub_pspp_success(&block)
    allow(ExportRelabeling::PsppLambdaClient).to receive(:compile) do |sps_path:, data_path:, output_path:|
      block&.call(sps_path, data_path)
      File.write(output_path, 'contenido sav simulado')
    end
  end

  def stub_mailer
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email).and_return(delivery)
    delivery
  end

  it 'extrae el zip, manda el .sps reescrito a la Lambda de PSPP, y manda el .sav resultante por mail' do
    stub_pspp_success
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(ExportDeliveryMailer).to have_received(:relabeled_export_email) do |recipients, project_id, sav_paths|
      expect(recipients).to eq(['destino@cliente.com'])
      expect(project_id).to eq('p123456')
      expect(sav_paths.length).to eq(1)
      expect(File.basename(sav_paths.first)).to eq('data.sav')
    end
  end

  it 'reescribe el label compuesto y apunta el FILE HANDLE/SAVE OUTFILE a los paths fijos que espera la Lambda' do
    captured_sps = nil
    captured_data_path = nil
    stub_pspp_success { |sps_path, data_path| captured_sps = File.read(sps_path); captured_data_path = data_path }
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(captured_sps).to include("Q1 'F1 | Pergunta | Texto de la pregunta'")
    expect(captured_sps).to include("NAME = '#{ExportRelabeling::PsppLambdaClient::LAMBDA_DATA_PATH}'")
    expect(captured_sps).not_to include('c:\temp')
    expect(captured_sps).to include("SAVE OUTFILE='#{ExportRelabeling::PsppLambdaClient::LAMBDA_SAV_PATH}'")
    # El .asc real (extraido del zip) se le pasa aparte a PsppLambdaClient --
    # nunca se sube el que el FILE HANDLE original apuntaba en Windows.
    expect(File.basename(captured_data_path)).to eq('data.asc')
  end

  it 'borra el zip original y el directorio de trabajo al terminar' do
    stub_pspp_success
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(File.exist?(zip_path)).to be false
  end

  # Antes de esta feature, un fallo de PSPP hacia que #perform levantara y
  # Sidekiq reintentara -- si segia fallando, el cliente nunca recibia
  # nada. Diego: "lo mas seguro seria que si algo falla se envie lo mismo
  # que se recibio... cubrimos el riesgo de que los datos se enviaron
  # aunque el formato no fuera perfecto". Ahora ese fallo (la Lambda no
  # responde, el compile revienta, etc.) cae al zip original, sin
  # re-etiquetar, en vez de no mandar nada.
  it 'si la Lambda de PSPP falla, manda el zip original sin cambios en vez de nada' do
    allow(ExportRelabeling::PsppLambdaClient).to receive(:compile).and_raise(StandardError, 'PSPP Lambda fallo')

    captured = {}
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths, relabeled: true|
      captured[:output_paths] = output_paths
      captured[:relabeled] = relabeled
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    expect { described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com']) }.not_to raise_error

    expect(captured[:output_paths]).to eq([zip_path])
    expect(captured[:relabeled]).to be false
  end
end
