# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe ExportRelabeling::EvidenceStore do
  let(:s3_client) { instance_double(Aws::S3::Client) }

  before { allow(Aws::S3::Client).to receive(:new).and_return(s3_client) }

  def with_zip
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'p803162949296_dcasar_594671327_sps.zip')
      File.write(path, 'zip original')
      yield path
    end
  end

  it 'sube el zip original cifrado, bajo evidence/AAAA/MM/DD/<proyecto>/, y devuelve la key' do
    with_zip do |path|
      uploaded = nil
      allow(s3_client).to receive(:put_object) { |args| uploaded = args.merge(body: args[:body].read) }

      key = described_class.save(zip_path: path, project_id: 'p803162949296', export_type: :spss)

      expect(key).to match(%r{\Aevidence/\d{4}/\d{2}/\d{2}/p803162949296/spss_\h{8}_p803162949296_dcasar_594671327_sps\.zip\z})
      expect(uploaded).to include(bucket: ExportRelabeling::PsppLambdaClient::BUCKET, key: key, body: 'zip original', server_side_encryption: 'AES256')
    end
  end

  it 'sin ID de proyecto usa "sin_proyecto" en la ruta' do
    with_zip do |path|
      allow(s3_client).to receive(:put_object)

      expect(described_class.save(zip_path: path, project_id: nil, export_type: :excel)).to include('/sin_proyecto/excel_')
    end
  end

  it 'es de mejor esfuerzo: si S3 falla devuelve nil y no levanta (el export sigue)' do
    with_zip do |path|
      allow(s3_client).to receive(:put_object).and_raise(StandardError, 'AccessDenied')

      expect(described_class.save(zip_path: path, project_id: 'p1', export_type: :spss)).to be_nil
    end
  end

  it 'si el zip no existe devuelve nil sin llamar a S3' do
    allow(s3_client).to receive(:put_object)

    expect(described_class.save(zip_path: '/no/existe.zip', project_id: 'p1', export_type: :spss)).to be_nil
    expect(s3_client).not_to have_received(:put_object)
  end

  it '.location arma la direccion s3:// completa para el aviso' do
    expect(described_class.location('evidence/a/b.zip')).to eq("s3://#{ExportRelabeling::PsppLambdaClient::BUCKET}/evidence/a/b.zip")
  end
end
