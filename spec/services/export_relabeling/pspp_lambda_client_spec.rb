# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe ExportRelabeling::PsppLambdaClient do
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:lambda_client) { instance_double(Aws::Lambda::Client) }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
    allow(Aws::Lambda::Client).to receive(:new).and_return(lambda_client)
  end

  def stub_lambda_success
    response = instance_double(Aws::Lambda::Types::InvocationResponse, function_error: nil)
    allow(lambda_client).to receive(:invoke).and_return(response)
  end

  it 'sube el .sps y el .dat a S3, invoca la Lambda, y baja el .sav resultante' do
    Dir.mktmpdir do |dir|
      sps_path = File.join(dir, 'input.sps')
      data_path = File.join(dir, 'data.asc')
      output_path = File.join(dir, 'output.sav')
      File.write(sps_path, 'contenido sps')
      File.write(data_path, 'contenido asc')

      uploaded = {}
      allow(s3_client).to receive(:put_object) { |args| uploaded[args[:key]] = args[:body] }

      stub_lambda_success
      invoked_payload = nil
      allow(lambda_client).to receive(:invoke) do |args|
        invoked_payload = JSON.parse(args[:payload])
        instance_double(Aws::Lambda::Types::InvocationResponse, function_error: nil)
      end

      sav_body = instance_double('body', read: 'contenido sav real')
      allow(s3_client).to receive(:get_object).and_return(instance_double(Aws::S3::Types::GetObjectOutput, body: sav_body))
      allow(s3_client).to receive(:delete_object)

      described_class.compile(sps_path: sps_path, data_path: data_path, output_path: output_path)

      expect(uploaded.keys).to contain_exactly(invoked_payload['sps_key'], invoked_payload['data_key'])
      expect(invoked_payload['bucket']).to eq(described_class::BUCKET)
      expect(File.read(output_path)).to eq('contenido sav real')
    end
  end

  it 'levanta un error si la Lambda devuelve function_error' do
    Dir.mktmpdir do |dir|
      sps_path = File.join(dir, 'input.sps')
      data_path = File.join(dir, 'data.asc')
      File.write(sps_path, 'x')
      File.write(data_path, 'x')

      allow(s3_client).to receive(:put_object)
      allow(s3_client).to receive(:delete_object)
      error_payload = instance_double('payload', read: '{"errorMessage":"algo salio mal"}')
      allow(lambda_client).to receive(:invoke).and_return(
        instance_double(Aws::Lambda::Types::InvocationResponse, function_error: 'Unhandled', payload: error_payload)
      )

      expect { described_class.compile(sps_path: sps_path, data_path: data_path, output_path: File.join(dir, 'out.sav')) }
        .to raise_error(/PSPP Lambda fallo/)
    end
  end

  it 'borra los 3 objetos de S3 del job al terminar, incluso si la Lambda fallo' do
    Dir.mktmpdir do |dir|
      sps_path = File.join(dir, 'input.sps')
      data_path = File.join(dir, 'data.asc')
      File.write(sps_path, 'x')
      File.write(data_path, 'x')

      allow(s3_client).to receive(:put_object)
      allow(lambda_client).to receive(:invoke).and_raise(StandardError, 'network error')
      deleted_keys = []
      allow(s3_client).to receive(:delete_object) { |args| deleted_keys << args[:key] }

      expect { described_class.compile(sps_path: sps_path, data_path: data_path, output_path: File.join(dir, 'out.sav')) }
        .to raise_error('network error')

      expect(deleted_keys.length).to eq(3)
    end
  end

  # p803162949296: "Task timed out after 90.00 seconds" -- PSPP compila ese archivo en
  # milisegundos, asi que es la Lambda (arranque en frio, etc.) y el reenvio funciono. Se
  # reintenta antes de dar el export por fallido.
  describe 'reintentos ante fallos transitorios de la Lambda' do
    let(:dir) { Dir.mktmpdir }
    let(:sps_path) { File.join(dir, 'input.sps') }
    let(:data_path) { File.join(dir, 'data.asc') }
    let(:output_path) { File.join(dir, 'output.sav') }
    let(:timeout_payload) do
      instance_double('payload', read: '{"errorType":"Sandbox.Timedout","errorMessage":"Task timed out after 90.00 seconds"}')
    end
    let(:timeout_response) do
      instance_double(Aws::Lambda::Types::InvocationResponse, function_error: 'Unhandled', payload: timeout_payload)
    end
    let(:ok_response) { instance_double(Aws::Lambda::Types::InvocationResponse, function_error: nil) }

    before do
      File.write(sps_path, 'x')
      File.write(data_path, 'x')
      allow(s3_client).to receive(:put_object)
      allow(s3_client).to receive(:delete_object)
      sav_body = instance_double('body', read: 'sav')
      allow(s3_client).to receive(:get_object).and_return(instance_double(Aws::S3::Types::GetObjectOutput, body: sav_body))
      allow_any_instance_of(described_class).to receive(:sleep)
    end

    after { FileUtils.rm_rf(dir) }

    def compile
      described_class.compile(sps_path: sps_path, data_path: data_path, output_path: output_path)
    end

    it 'si la primera invocacion da timeout y la segunda sale bien, termina OK (sin subir los archivos de nuevo)' do
      allow(lambda_client).to receive(:invoke).and_return(timeout_response, ok_response)

      expect { compile }.not_to raise_error

      expect(lambda_client).to have_received(:invoke).twice
      expect(s3_client).to have_received(:put_object).twice # .sps y .dat, una sola vez
      expect(File.read(output_path)).to eq('sav')
    end

    it 'si falla todas las veces, levanta el error despues de 3 intentos' do
      allow(lambda_client).to receive(:invoke).and_return(timeout_response)

      expect { compile }.to raise_error(described_class::TransientLambdaError, /Task timed out/)

      expect(lambda_client).to have_received(:invoke).exactly(3).times
    end

    it 'reintenta tambien ante un error de red y ante throttling' do
      allow(lambda_client).to receive(:invoke)
        .and_raise(Seahorse::Client::NetworkingError.new(Net::ReadTimeout.new('timeout')))
      expect { compile }.to raise_error(Seahorse::Client::NetworkingError)
      expect(lambda_client).to have_received(:invoke).exactly(3).times
    end

    it 'NO reintenta un fallo de PSPP (no genero el .sav): fallaria igual' do
      pspp_failure = instance_double('payload', read: '{"errorMessage":"PSPP no genero el .sav esperado. exit=1"}')
      allow(lambda_client).to receive(:invoke).and_return(
        instance_double(Aws::Lambda::Types::InvocationResponse, function_error: 'Unhandled', payload: pspp_failure)
      )

      expect { compile }.to raise_error(RuntimeError, /PSPP no genero/)

      expect(lambda_client).to have_received(:invoke).once
    end

    it 'espera entre intentos (5 s y despues 15 s)' do
      allow(lambda_client).to receive(:invoke).and_return(timeout_response, timeout_response, ok_response)
      delays = []
      allow_any_instance_of(described_class).to receive(:sleep) { |_, seconds| delays << seconds }

      compile

      expect(delays).to eq([5, 15])
    end
  end
end
