require 'rails_helper'

RSpec.describe DeviceToken, type: :model do
  let(:user) { User.create!(encrypted_email: Digest::MD5.hexdigest('a@example.com'), jti: SecureRandom.uuid) }

  it 'is valid with a supported platform' do
    token = DeviceToken.new(user: user, token: 'abc123', platform: 'ios')

    expect(token).to be_valid
  end

  it 'is invalid with an unsupported platform' do
    token = DeviceToken.new(user: user, token: 'abc123', platform: 'windows_phone')

    expect(token).not_to be_valid
  end

  it 'requires a unique token' do
    DeviceToken.create!(user: user, token: 'abc123', platform: 'ios')
    duplicate = DeviceToken.new(user: user, token: 'abc123', platform: 'android')

    expect(duplicate).not_to be_valid
    expect do
      duplicate.save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
