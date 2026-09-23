require 'rails_helper'

RSpec.describe 'Device tokens API', type: :request do
  let(:user) { User.create!(encrypted_email: Digest::MD5.hexdigest('a@example.com'), jti: SecureRandom.uuid) }
  let(:other_user) { User.create!(encrypted_email: Digest::MD5.hexdigest('b@example.com'), jti: SecureRandom.uuid) }

  def auth_headers(for_user)
    token = JWT.encode({ 'jti' => for_user.jti }, nil, 'none')
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/device_tokens' do
    it 'requires authentication' do
      post '/api/v1/device_tokens', params: { token: 'abc123', platform: 'ios' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'registers a new token for the current user' do
      post '/api/v1/device_tokens', params: { token: 'abc123', platform: 'ios' }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(DeviceToken.find_by(token: 'abc123').user).to eq(user)
    end

    it 'reassigns an existing token to whoever logs in with it next' do
      DeviceToken.create!(user: other_user, token: 'abc123', platform: 'ios')

      post '/api/v1/device_tokens', params: { token: 'abc123', platform: 'ios' }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(DeviceToken.where(token: 'abc123').count).to eq(1)
      expect(DeviceToken.find_by(token: 'abc123').user).to eq(user)
    end
  end

  describe 'DELETE /api/v1/device_tokens' do
    it "removes the token from the current user's account" do
      DeviceToken.create!(user: user, token: 'abc123', platform: 'ios')

      delete '/api/v1/device_tokens', params: { token: 'abc123' }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(DeviceToken.exists?(token: 'abc123')).to be false
    end

    it "does not remove another user's token" do
      DeviceToken.create!(user: other_user, token: 'abc123', platform: 'ios')

      delete '/api/v1/device_tokens', params: { token: 'abc123' }, headers: auth_headers(user)

      expect(DeviceToken.exists?(token: 'abc123')).to be true
    end
  end
end
