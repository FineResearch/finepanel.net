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
end
