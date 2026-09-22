require 'rails_helper'

RSpec.describe NewsSocialDiscoveryWorker do
  let(:specialty) { Specialty.create!(name: 'Cardiologia', slug: "cardiologia-#{SecureRandom.hex(4)}") }
  let(:other_specialty) { Specialty.create!(name: 'Dermatologia', slug: "dermatologia-#{SecureRandom.hex(4)}") }
  let(:article) do
    Article.create!(
      dynamed_id: "DM-#{SecureRandom.hex(4)}",
      title: 'Articulo de prueba',
      slug: "/topics/test-#{SecureRandom.hex(4)}",
      specialty: specialty,
    )
  end
  let(:news_feed) { NewsFeed.create!(text: "texto de la noticia #{SecureRandom.hex(4)}", specialty: specialty, article: article) }
  let(:other_news_feed) do
    NewsFeed.create!(text: "otra noticia #{SecureRandom.hex(4)}", specialty: specialty, article: article)
  end
  let(:campaign) do
    NewsSocialDiscoveryCampaign.create!(
      news_feed: news_feed, triggered_at: Time.current, useful_count_at_trigger: 10, comment_count_at_trigger: 1,
    )
  end

  before do
    allow(NewsConversationReminderMailer).to receive(:news_social_discovery_email).and_return(double(deliver_later: true))
  end

  def create_user(email, opt_out: false)
    User.create!(encrypted_email: Digest::MD5.hexdigest(email), jti: SecureRandom.uuid, comment_notifications_opt_out: opt_out)
  end

  def view!(user, feed: news_feed, spec: specialty, email: nil)
    NewsFeedView.create!(user: user, news_feed: feed, specialty: spec, email: email || "#{user.id}@example.com")
  end

  it 'notifies an eligible reader: same specialty, in the reader base, has not read this article' do
    reader = create_user('reader@example.com')
    view!(reader, feed: other_news_feed)

    described_class.new.perform(campaign.id)

    expect(Notification.exists?(user: reader, news_feed: news_feed, notification_type: 'news_social_discovery')).to be true
    expect(NewsConversationReminderMailer).to have_received(:news_social_discovery_email).with(
      "#{reader.id}@example.com", 'es', news_feed, reader, 10
    )
  end

  it 'excludes a reader who already read this exact article' do
    reader = create_user('reader@example.com')
    view!(reader, feed: news_feed)

    described_class.new.perform(campaign.id)

    expect(Notification.exists?(user: reader, news_feed: news_feed, notification_type: 'news_social_discovery')).to be false
  end

  it 'excludes a reader whose captured specialty does not match the article' do
    reader = create_user('reader@example.com')
    view!(reader, feed: other_news_feed, spec: other_specialty)

    described_class.new.perform(campaign.id)

    expect(Notification.count).to eq(0)
  end

  it 'never considers a user who has no NewsFeedView row at all' do
    create_user('never-read@example.com')

    described_class.new.perform(campaign.id)

    expect(Notification.count).to eq(0)
  end

  it 'excludes a reader notified 15 days ago (within the 30-day cooldown)' do
    reader = create_user('reader@example.com')
    view!(reader, feed: other_news_feed)
    Notification.create!(user: reader, news_feed: other_news_feed, notification_type: 'news_social_discovery').tap do |n|
      n.update_column(:created_at, 15.days.ago)
    end

    described_class.new.perform(campaign.id)

    expect(Notification.exists?(user: reader, news_feed: news_feed, notification_type: 'news_social_discovery')).to be false
  end

  it 'includes a reader notified 31 days ago (past the 30-day cooldown)' do
    reader = create_user('reader@example.com')
    view!(reader, feed: other_news_feed)
    Notification.create!(user: reader, news_feed: other_news_feed, notification_type: 'news_social_discovery').tap do |n|
      n.update_column(:created_at, 31.days.ago)
    end

    described_class.new.perform(campaign.id)

    expect(Notification.exists?(user: reader, news_feed: news_feed, notification_type: 'news_social_discovery')).to be true
  end

  it 'excludes a reader who opted out of comment notifications' do
    reader = create_user('reader@example.com', opt_out: true)
    view!(reader, feed: other_news_feed)

    described_class.new.perform(campaign.id)

    expect(Notification.count).to eq(0)
  end

  it 'does not duplicate notifications or emails on a Sidekiq retry' do
    reader = create_user('reader@example.com')
    view!(reader, feed: other_news_feed)

    described_class.new.perform(campaign.id)
    described_class.new.perform(campaign.id)

    expect(Notification.where(user: reader, news_feed: news_feed, notification_type: 'news_social_discovery').count).to eq(1)
    expect(NewsConversationReminderMailer).to have_received(:news_social_discovery_email).once
  end

  it 'recomputes recipient_count from Notification, not accumulated in Ruby' do
    reader_a = create_user('a@example.com')
    reader_b = create_user('b@example.com')
    view!(reader_a, feed: other_news_feed)
    view!(reader_b, feed: other_news_feed)

    described_class.new.perform(campaign.id)

    expect(campaign.reload.recipient_count).to eq(2)
    expect(campaign.reload.eligible_recipient_count).to eq(2)
  end
end
