require 'rails_helper'

RSpec.describe CommentReplyNotificationWorker do
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
  let(:author) { create_user('author@example.com') }
  let(:replier_a) { create_user('a@example.com') }
  let(:replier_b) { create_user('b@example.com') }

  let(:comment) do
    NewsComment.create!(
      text: 'comentario de prueba',
      user: author,
      news_feed: news_feed,
      user_info: { 'email' => 'author@example.com', 'complete_name' => 'Autor Test' },
    )
  end

  before do
    allow(NewsConversationReminderMailer).to receive(:comment_reply_email).and_return(double(deliver_later: true))
  end

  def create_user(email)
    User.create!(encrypted_email: Digest::MD5.hexdigest(email), jti: SecureRandom.uuid)
  end

  def reply_to(comment_to_reply, user)
    NewsComment.create!(
      text: 'una respuesta',
      user: user,
      news_feed: news_feed,
      user_info: { 'email' => "#{user.id}@example.com" },
      parent_comment: comment_to_reply,
    )
  end

  it 'notifies the parent comment author on the first reply' do
    reply = reply_to(comment, replier_a)

    described_class.new.perform(reply.id)

    expect(NewsConversationReminderMailer).to have_received(:comment_reply_email).once.with(
      'author@example.com', 'es', news_feed, author
    )
    expect(
      Notification.exists?(user: author, news_feed: news_feed, notification_type: 'comment_reply', news_comment: comment)
    ).to be true
  end

  it 'never sends more than one notification for the same comment, even with several replies' do
    reply_a = reply_to(comment, replier_a)
    reply_b = reply_to(comment, replier_b)

    described_class.new.perform(reply_a.id)
    described_class.new.perform(reply_b.id)

    expect(NewsConversationReminderMailer).to have_received(:comment_reply_email).once
    expect(
      Notification.where(user: author, news_feed: news_feed, notification_type: 'comment_reply', news_comment: comment).count
    ).to eq(1)
  end

  it 'does not notify when the author replies to their own comment' do
    reply = reply_to(comment, author)

    described_class.new.perform(reply.id)

    expect(NewsConversationReminderMailer).not_to have_received(:comment_reply_email)
    expect(Notification.count).to eq(0)
  end

  it 'does nothing for a top-level comment (no parent)' do
    described_class.new.perform(comment.id)

    expect(NewsConversationReminderMailer).not_to have_received(:comment_reply_email)
    expect(Notification.count).to eq(0)
  end
end
