require 'rails_helper'

RSpec.describe PushNotifier do
  let(:user) { User.create!(encrypted_email: Digest::MD5.hexdigest('a@example.com'), jti: SecureRandom.uuid) }
  let!(:device_token) { DeviceToken.create!(user: user, token: 'device-token-1', platform: 'ios') }

  let(:service_account) do
    {
      project_id: 'fine-panel-test',
      client_email: 'firebase-adminsdk@fine-panel-test.iam.gserviceaccount.com',
      # Clave RSA generada solo para el test -- JWT.encode necesita una
      # clave privada real con forma valida, el contenido no importa.
      private_key: OpenSSL::PKey::RSA.new(1024).to_pem,
    }.to_json
  end

  def stub_token_exchange(access_token: 'fake-access-token')
    token_response = instance_double(Net::HTTPOK, body: { access_token: access_token }.to_json)
    allow(Net::HTTP).to receive(:post_form)
      .with(URI(described_class::GOOGLE_TOKEN_URI), hash_including(grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer'))
      .and_return(token_response)
  end

  def stub_fcm_send(code: '200', body: '{}')
    http_double = instance_double(Net::HTTP)
    response_double = instance_double(Net::HTTPResponse, code: code, body: body)

    allow(http_double).to receive(:request).and_return(response_double)
    # and_yield por si solo no reenvia el valor de retorno del bloque -- el
    # codigo real depende de que Net::HTTP.start devuelva justamente lo que
    # el bloque devuelve (la response), por eso se arma el stub a mano.
    allow(Net::HTTP).to receive(:start) { |*_args, &block| block.call(http_double) }
  end

  around do |example|
    original = ENV['FCM_SERVICE_ACCOUNT_JSON_BASE64']
    ENV['FCM_SERVICE_ACCOUNT_JSON_BASE64'] = Base64.strict_encode64(service_account)
    # Memory store real y aislado por test -- no depende de que
    # config.cache_store del entorno de test sea uno que realmente
    # persista entre llamadas (ej. :null_store no lo haria).
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    example.run
    ENV['FCM_SERVICE_ACCOUNT_JSON_BASE64'] = original
  end

  it 'does nothing when there are no user_ids' do
    expect(Net::HTTP).not_to receive(:start)

    described_class.new([], 'hola').send_notification
  end

  it 'does nothing when the message is blank' do
    expect(Net::HTTP).not_to receive(:start)

    described_class.new([user.id], '').send_notification
  end

  it "sends a notification to each of the user's device tokens" do
    stub_token_exchange
    stub_fcm_send

    described_class.new([user.id], 'Nueva encuesta disponible').send_notification

    expect(Net::HTTP).to have_received(:start).once
  end

  it 'reuses the cached access token across multiple sends instead of re-fetching it' do
    stub_token_exchange
    stub_fcm_send
    other_user = User.create!(encrypted_email: Digest::MD5.hexdigest('b@example.com'), jti: SecureRandom.uuid)
    DeviceToken.create!(user: other_user, token: 'device-token-2', platform: 'android')

    described_class.new([user.id], 'primer envio').send_notification
    described_class.new([other_user.id], 'segundo envio').send_notification

    expect(Net::HTTP).to have_received(:post_form).once
  end

  it 'deletes the device token when FCM reports it as unregistered' do
    stub_token_exchange
    stub_fcm_send(code: '404', body: { error: { status: 'UNREGISTERED' } }.to_json)

    described_class.new([user.id], 'hola').send_notification

    expect(DeviceToken.exists?(token: 'device-token-1')).to be false
  end

  it 'keeps the device token on a transient server error' do
    stub_token_exchange
    stub_fcm_send(code: '500', body: { error: { status: 'INTERNAL' } }.to_json)

    described_class.new([user.id], 'hola').send_notification

    expect(DeviceToken.exists?(token: 'device-token-1')).to be true
  end
end
