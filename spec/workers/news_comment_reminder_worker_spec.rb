require 'rails_helper'

RSpec.describe NewsCommentReminderWorker do
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
  let(:user_d) { create_user('d@example.com') }

  subject(:perform) { described_class.new.perform(news_feed.id) }

  before do
    allow(NewsConversationReminderMailer).to receive(:reminder_email).and_return(double(deliver_later: true))
  end

  def create_user(email)
    User.create!(
      encrypted_email: Digest::MD5.hexdigest(email),
      jti: SecureRandom.uuid,
    )
  end

  def create_comment(user, email, created_at:, country: nil)
    comment = NewsComment.create!(
      text: 'comentario de prueba',
      user: user,
      news_feed: news_feed,
      user_info: { 'email' => email, 'country' => country, 'complete_name' => 'Doctor Test' },
    )
    comment.update_column(:created_at, created_at)
    comment
  end

  it 'sends a reminder to the author once 3 subsequent comments from at least 2 distinct authors were posted' do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute, country: 'Argentina')
    create_comment(user_c, 'c@example.com', created_at: t + 2.minutes, country: 'Brasil')
    create_comment(user_d, 'd@example.com', created_at: t + 3.minutes, country: 'Colombia')

    perform

    expect(NewsConversationReminderMailer).to have_received(:reminder_email).once.with(
      'a@example.com', 'es', news_feed, match_array(%w[Argentina Brasil Colombia]), user_a
    )
    expect(
      Notification.exists?(user: user_a, news_feed: news_feed, notification_type: 'news_conversation_reminder')
    ).to be true
  end

  it 'does not send a reminder when there are only 1-2 subsequent comments' do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)

    perform

    expect(NewsConversationReminderMailer).not_to have_received(:reminder_email)
    expect(Notification.count).to eq(0)
  end

  it 'does not send a reminder when the subsequent comments come from a single author' do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)
    create_comment(user_b, 'b@example.com', created_at: t + 2.minutes)
    create_comment(user_b, 'b@example.com', created_at: t + 3.minutes)

    perform

    expect(NewsConversationReminderMailer).not_to have_received(:reminder_email)
  end

  it "does not count the recipient's own later comments towards the subsequent threshold" do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)
    create_comment(user_a, 'a@example.com', created_at: t + 2.minutes)
    create_comment(user_c, 'c@example.com', created_at: t + 3.minutes)

    perform

    expect(NewsConversationReminderMailer).not_to have_received(:reminder_email)
  end

  it 'never sends more than one reminder to the same user for the same news item' do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)
    create_comment(user_c, 'c@example.com', created_at: t + 2.minutes)
    create_comment(user_d, 'd@example.com', created_at: t + 3.minutes)

    perform

    create_comment(user_b, 'b@example.com', created_at: t + 4.minutes)
    create_comment(user_c, 'c@example.com', created_at: t + 5.minutes)
    create_comment(user_d, 'd@example.com', created_at: t + 6.minutes)

    perform

    expect(NewsConversationReminderMailer).to have_received(:reminder_email).once
    expect(Notification.where(user: user_a, news_feed: news_feed).count).to eq(1)
  end

  it 're-engaging (commenting again) does not trigger a second reminder for the same news item' do
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute)
    create_comment(user_c, 'c@example.com', created_at: t + 2.minutes)
    create_comment(user_d, 'd@example.com', created_at: t + 3.minutes)

    perform

    create_comment(user_a, 'a@example.com', created_at: t + 4.minutes)
    create_comment(user_b, 'b@example.com', created_at: t + 5.minutes)
    create_comment(user_c, 'c@example.com', created_at: t + 6.minutes)
    create_comment(user_d, 'd@example.com', created_at: t + 7.minutes)

    perform

    expect(NewsConversationReminderMailer).to have_received(:reminder_email).once
  end

  it 'still reserves the notification but does not send the mail when the recipient opted out' do
    user_a.update!(comment_notifications_opt_out: true)
    t = Time.current
    create_comment(user_a, 'a@example.com', created_at: t)
    create_comment(user_b, 'b@example.com', created_at: t + 1.minute, country: 'Argentina')
    create_comment(user_c, 'c@example.com', created_at: t + 2.minutes, country: 'Brasil')
    create_comment(user_d, 'd@example.com', created_at: t + 3.minutes, country: 'Colombia')

    perform

    expect(NewsConversationReminderMailer).not_to have_received(:reminder_email)
    expect(
      Notification.exists?(user: user_a, news_feed: news_feed, notification_type: 'news_conversation_reminder')
    ).to be true
  end

  it 'enforces at most one notification per user/news_feed/type at the database level' do
    Notification.create!(user: user_a, news_feed: news_feed, notification_type: 'news_conversation_reminder')

    expect do
      Notification.new(user: user_a, news_feed: news_feed, notification_type: 'news_conversation_reminder').save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
