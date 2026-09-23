require 'rails_helper'

RSpec.describe SyncSurveyLinksWorker do
  def create_user(email, language, with_device_token: true)
    user = User.create!(encrypted_email: Digest::MD5.hexdigest(email), jti: SecureRandom.uuid, language: language)
    DeviceToken.create!(user: user, token: "token-#{user.id}", platform: 'ios') if with_device_token

    user
  end

  def write_feed_file(rows)
    file = Tempfile.new(['p12345_feed', '.txt'])
    file.write("resp_id\tlink\tvariables\n")
    rows.each { |row| file.write("#{row.join("\t")}\n") }
    file.close

    file.path
  end

  before do
    allow(PushNotificationsWorker).to receive(:perform_async)
    allow(File).to receive(:delete)
  end

  it 'buckets user ids (not emails) per language, only for users with a registered device token' do
    es_user = create_user('es@example.com', 'es')
    por_user = create_user('por@example.com', 'por')
    no_device_user = create_user('no-device@example.com', 'es', with_device_token: false)

    feed_path = write_feed_file([
      ['1', 'https://survey.example.com/p12345?s=SPANEL1', 'es@example.com'],
      ['2', 'https://survey.example.com/p12345?s=SPANEL2', 'por@example.com'],
      ['3', 'https://survey.example.com/p12345?s=SPANEL3', 'no-device@example.com'],
    ])

    described_class.new.perform(feed_path, feed_path, { 'es' => 'Nueva encuesta', 'por' => 'Nova pesquisa' })

    expect(PushNotificationsWorker).to have_received(:perform_async).with([es_user.id], 'Nueva encuesta')
    expect(PushNotificationsWorker).to have_received(:perform_async).with([por_user.id], 'Nova pesquisa')
  end
end
