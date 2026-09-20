require 'rails_helper'

RSpec.describe User do
  def create_user(email)
    User.create!(encrypted_email: Digest::MD5.hexdigest(email), jti: SecureRandom.uuid)
  end

  describe '.find_from_unsubscribe_token / #comment_notifications_unsubscribe_token' do
    it 'round-trips: a token generated for a user resolves back to that same user' do
      user = create_user('reader@example.com')

      token = user.comment_notifications_unsubscribe_token

      expect(User.find_from_unsubscribe_token(token)).to eq(user)
    end

    it 'returns nil for a tampered/invalid token' do
      create_user('reader@example.com')

      expect(User.find_from_unsubscribe_token('not-a-real-token')).to be_nil
    end

    it 'returns nil for a token signed for a different purpose' do
      user = create_user('reader@example.com')
      other_purpose_token = Rails.application.message_verifier(:something_else).generate(user.id)

      expect(User.find_from_unsubscribe_token(other_purpose_token)).to be_nil
    end

    it 'returns nil when no user matches the id encoded in the token' do
      token = Rails.application.message_verifier(:comment_notifications_unsubscribe).generate(0)

      expect(User.find_from_unsubscribe_token(token)).to be_nil
    end
  end
end
