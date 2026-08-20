require 'rails_helper'

RSpec.describe FirstCommentReplyWorker do
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

  let(:user_a) { create_user('a@example.com') }
  let(:user_b) { create_user('b@example.com') }
  let(:user_c) { create_user('c@example.com') }

  subject(:perform) { described_class.new.perform(news_feed.id) }

  before do
    allow(NewsConversationReminderMailer).to receive(:first_reply_email).and_return(double(deliver_later: true))
  end

  def create_user(email)
    User.create!(
      encrypted_email: Digest::MD5.hexdigest(email),
      jti: SecureRandom.uuid,
    )
  end

  def create_comment(user, email, created_at:)
    comment = NewsComment.create!(
      text: 'comentario de prueba',
      user: user,
      news_feed: news_feed,
      user_info: { 'email' => email, 'complete_name' => 'Doctor Test' },
    )
    comment.update_column(:created_at, created_at)
    comment
  end

  it 'notifies the first commenter once a second comment (from another user) arrives' do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)

    perform

    expect(NewsConversationReminderMailer).to have_received(:first_reply_email).once.with(
      'a@example.com', 'es', news_feed
    )
    expect(
      Notification.exists?(user: user_a, news_feed: news_feed, notification_type: 'first_comment_reply')
    ).to be true
  end

  it 'does not notify when there is still only one comment' do
    create_comment(user_a, 'a@example.com', created_at: Time.current)

    perform

    expect(NewsConversationReminderMailer).not_to have_received(:first_reply_email)
    expect(Notification.count).to eq(0)
  end

  it 'never sends more than one notification to the same first commenter for the same news item' do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)

    perform

    create_comment(user_c, 'c@example.com', created_at: t + 2.minutes)

    perform

    expect(NewsConversationReminderMailer).to have_received(:first_reply_email).once
    expect(Notification.where(user: user_a, news_feed: news_feed).count).to eq(1)
  end

  it 'enforces at most one notification per user/news_feed/type at the database level' do
    Notification.create!(user: user_a, news_feed: news_feed, notification_type: 'first_comment_reply')

    expect do
      Notification.new(user: user_a, news_feed: news_feed, notification_type: 'first_comment_reply').save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'does not interfere with NewsCommentReminderWorker (different notification_type, both can fire for the same news item)' do
    allow(NewsConversationReminderMailer).to receive(:reminder_email).and_return(double(deliver_later: true))

    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)

    perform # first_comment_reply trigger (comment #2)

    create_comment(user_c, 'c@example.com', created_at: t + 2.minutes)
    create_comment(user_b, 'b@example.com', created_at: t + 3.minutes)
    create_comment(user_c, 'c@example.com', created_at: t + 4.minutes)

    NewsCommentReminderWorker.new.perform(news_feed.id)

    expect(
      Notification.where(user: user_a, news_feed: news_feed, notification_type: 'first_comment_reply').count
    ).to eq(1)
    expect(
      Notification.where(user: user_a, news_feed: news_feed, notification_type: 'news_conversation_reminder').count
    ).to eq(1)
  end
end
