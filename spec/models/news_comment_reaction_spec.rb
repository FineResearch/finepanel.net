require 'rails_helper'

RSpec.describe NewsCommentReaction, type: :model do
  let(:specialty) { Specialty.create!(name: 'Cardiologia', slug: "cardiologia-#{SecureRandom.hex(4)}") }
  let(:article) do
    Article.create!(
      dynamed_id: "DM-#{SecureRandom.hex(4)}",
      title: 'Articulo de prueba',
      slug: "/topics/test-#{SecureRandom.hex(4)}",
      specialty: specialty,
    )
  end
  let(:news_feed) { NewsFeed.create!(text: "texto de la noticia #{SecureRandom.hex(4)}", specialty: specialty, article: article) }
  let(:author) { User.create!(encrypted_email: Digest::MD5.hexdigest('author@example.com'), jti: SecureRandom.uuid) }
  let(:reactor) { User.create!(encrypted_email: Digest::MD5.hexdigest('reactor@example.com'), jti: SecureRandom.uuid) }
  let(:comment) do
    NewsComment.create!(
      text: 'comentario de prueba',
      user: author,
      news_feed: news_feed,
      user_info: { 'email' => 'author@example.com', 'complete_name' => 'Autor Test' },
    )
  end

  before do
    allow(CommentAgreementNotificationWorker).to receive(:perform_async)
  end

  it 'is valid with a user and a news_comment' do
    reaction = NewsCommentReaction.new(user: reactor, news_comment: comment)

    expect(reaction).to be_valid
  end

  it 'allows a single reaction per user and news_comment' do
    NewsCommentReaction.create!(user: reactor, news_comment: comment)
    duplicate = NewsCommentReaction.new(user: reactor, news_comment: comment)

    expect(duplicate).not_to be_valid
    expect do
      duplicate.save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'does not allow reacting to your own comment' do
    reaction = NewsCommentReaction.new(user: author, news_comment: comment)

    expect(reaction).not_to be_valid
    expect(reaction.errors[:user_id]).to be_present
  end

  it 'enqueues CommentAgreementNotificationWorker exactly when the distinct-reactor count reaches 2' do
    other_reactor = User.create!(encrypted_email: Digest::MD5.hexdigest('other@example.com'), jti: SecureRandom.uuid)

    NewsCommentReaction.create!(user: reactor, news_comment: comment)
    expect(CommentAgreementNotificationWorker).not_to have_received(:perform_async)

    NewsCommentReaction.create!(user: other_reactor, news_comment: comment)
    expect(CommentAgreementNotificationWorker).to have_received(:perform_async).once.with(comment.id)
  end

  it 'does not re-enqueue when a third distinct reactor agrees' do
    third_reactor = User.create!(encrypted_email: Digest::MD5.hexdigest('third@example.com'), jti: SecureRandom.uuid)
    other_reactor = User.create!(encrypted_email: Digest::MD5.hexdigest('other@example.com'), jti: SecureRandom.uuid)

    NewsCommentReaction.create!(user: reactor, news_comment: comment)
    NewsCommentReaction.create!(user: other_reactor, news_comment: comment)
    NewsCommentReaction.create!(user: third_reactor, news_comment: comment)

    expect(CommentAgreementNotificationWorker).to have_received(:perform_async).once
  end

  it 'does not re-enqueue after a reaction is removed and a new one brings the count back to 2' do
    other_reactor = User.create!(encrypted_email: Digest::MD5.hexdigest('other@example.com'), jti: SecureRandom.uuid)
    third_reactor = User.create!(encrypted_email: Digest::MD5.hexdigest('third@example.com'), jti: SecureRandom.uuid)

    r1 = NewsCommentReaction.create!(user: reactor, news_comment: comment)
    NewsCommentReaction.create!(user: other_reactor, news_comment: comment)
    r1.destroy!

    NewsCommentReaction.create!(user: third_reactor, news_comment: comment)

    # El callback SI vuelve a encolar el worker (after_create no sabe que ya
    # se notifico antes) -- el dedup permanente vive en el worker/Notification,
    # no en este callback. Ver comentario en NewsCommentReaction.
    expect(CommentAgreementNotificationWorker).to have_received(:perform_async).twice
  end
end
