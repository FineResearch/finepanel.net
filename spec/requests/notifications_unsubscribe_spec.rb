require 'rails_helper'

RSpec.describe 'GET /api/v1/notifications/unsubscribe', type: :request do
  def create_user(email)
    User.create!(encrypted_email: Digest::MD5.hexdigest(email), jti: SecureRandom.uuid)
  end

  it 'opts the user out and returns success, with no auth required' do
    user = create_user('reader@example.com')
    token = user.comment_notifications_unsubscribe_token

    get '/api/v1/notifications/unsubscribe', params: { token: token }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['success']).to eq(true)

    user.reload
    expect(user.comment_notifications_opt_out).to be true
    expect(user.comment_notifications_opt_out_at).to be_present
  end

  it 'is idempotent -- clicking the link twice does not error' do
    user = create_user('reader@example.com')
    token = user.comment_notifications_unsubscribe_token

    get '/api/v1/notifications/unsubscribe', params: { token: token }
    get '/api/v1/notifications/unsubscribe', params: { token: token }

    expect(response).to have_http_status(:ok)
    expect(user.reload.comment_notifications_opt_out).to be true
  end

  it 'returns an error for an invalid token and does not opt anyone out' do
    create_user('reader@example.com')

    get '/api/v1/notifications/unsubscribe', params: { token: 'not-a-real-token' }

    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body['success']).to eq(false)
    expect(User.where(comment_notifications_opt_out: true).count).to eq(0)
  end
end
