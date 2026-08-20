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
end
