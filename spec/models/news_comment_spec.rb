require 'rails_helper'

RSpec.describe NewsComment do
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

  def create_user(email)
    User.create!(
      encrypted_email: Digest::MD5.hexdigest(email),
      jti: SecureRandom.uuid,
    )
  end

  def create_comment(email)
    NewsComment.create!(
      text: 'comentario de prueba',
      user: create_user(email),
      news_feed: news_feed,
      user_info: { 'email' => email, 'complete_name' => 'Doctor Test' },
    )
  end

  # notify_first_commenter_on_reply solo debe encolar el worker cuando el
  # comentario recien creado es exactamente el segundo de la noticia -- no
  # el primero (no hay a quien avisar todavia) ni el tercero en adelante
  # (ya se avisa una unica vez, en el segundo).
  describe '#notify_first_commenter_on_reply' do
    before { FirstCommentReplyWorker.jobs.clear }

    it 'does not enqueue the worker for the first comment on a news item' do
      create_comment('a@example.com')

      expect(FirstCommentReplyWorker.jobs.size).to eq(0)
    end

    it 'enqueues the worker exactly when the second comment is created' do
      create_comment('a@example.com')
      create_comment('b@example.com')

      expect(FirstCommentReplyWorker.jobs.size).to eq(1)
      expect(FirstCommentReplyWorker.jobs.first['args']).to eq([news_feed.id])
    end

    it 'does not enqueue the worker again for a third or later comment' do
      create_comment('a@example.com')
      create_comment('b@example.com')
      FirstCommentReplyWorker.jobs.clear
      create_comment('c@example.com')

      expect(FirstCommentReplyWorker.jobs.size).to eq(0)
    end
  end

  describe '#parent_comment_must_be_top_level' do
    it 'allows replying to a top-level comment' do
      parent = create_comment('a@example.com')
      reply = NewsComment.new(
        text: 'una respuesta',
        user: create_user('b@example.com'),
        news_feed: news_feed,
        user_info: { 'email' => 'b@example.com' },
        parent_comment: parent,
      )

      expect(reply).to be_valid
    end

    it 'rejects replying to a reply (only 1 level of nesting allowed)' do
      parent = create_comment('a@example.com')
      reply = NewsComment.create!(
        text: 'una respuesta',
        user: create_user('b@example.com'),
        news_feed: news_feed,
        user_info: { 'email' => 'b@example.com' },
        parent_comment: parent,
      )
      reply_to_reply = NewsComment.new(
        text: 'otra respuesta',
        user: create_user('c@example.com'),
        news_feed: news_feed,
        user_info: { 'email' => 'c@example.com' },
        parent_comment: reply,
      )

      expect(reply_to_reply).not_to be_valid
    end
  end

  describe '#notify_parent_comment_author' do
    before { CommentReplyNotificationWorker.jobs.clear }

    it 'enqueues the worker when a comment is a reply' do
      parent = create_comment('a@example.com')
      reply = NewsComment.create!(
        text: 'una respuesta',
        user: create_user('b@example.com'),
        news_feed: news_feed,
        user_info: { 'email' => 'b@example.com' },
        parent_comment: parent,
      )

      expect(CommentReplyNotificationWorker.jobs.size).to eq(1)
      expect(CommentReplyNotificationWorker.jobs.first['args']).to eq([reply.id])
    end

    it 'does not enqueue the worker for a top-level comment' do
      create_comment('a@example.com')

      expect(CommentReplyNotificationWorker.jobs.size).to eq(0)
    end
  end
end
