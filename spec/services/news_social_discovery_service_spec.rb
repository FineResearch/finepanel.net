require 'rails_helper'

RSpec.describe NewsSocialDiscoveryService do
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

  before do
    allow(NewsSocialDiscoveryWorker).to receive(:perform_async)
  end

  def create_user(email)
    User.create!(encrypted_email: Digest::MD5.hexdigest(email), jti: SecureRandom.uuid)
  end

  # Ambos hooks (NewsFeedReaction#after_save, NewsComment#after_create) ya
  # estan encadenados en los modelos -- crear estos registros dispara
  # NewsSocialDiscoveryService.evaluate solo, no hace falta llamarlo aparte.
  def react_useful!(user)
    NewsFeedReaction.create!(user: user, news_feed: news_feed, useful: true)
  end

  def comment!(user)
    NewsComment.create!(text: 'comentario de prueba', user: user, news_feed: news_feed, user_info: { 'email' => "#{user.id}@example.com" })
  end

  def react_useful_n_times(count)
    count.times { |i| react_useful!(create_user("useful-#{i}-#{SecureRandom.hex(2)}@example.com")) }
  end

  it 'does not trigger with 9 useful reactions and 1 comment' do
    react_useful_n_times(9)
    comment!(create_user('commenter@example.com'))

    expect(NewsSocialDiscoveryCampaign.count).to eq(0)
    expect(NewsSocialDiscoveryWorker).not_to have_received(:perform_async)
  end

  it 'does not trigger with 10 useful reactions and 0 comments' do
    react_useful_n_times(10)

    expect(NewsSocialDiscoveryCampaign.count).to eq(0)
  end

  it 'triggers with 10 useful reactions and 1 comment' do
    react_useful_n_times(10)
    comment!(create_user('commenter@example.com'))

    campaign = NewsSocialDiscoveryCampaign.find_by!(news_feed: news_feed)
    expect(campaign.useful_count_at_trigger).to eq(10)
    expect(campaign.comment_count_at_trigger).to eq(1)
    expect(NewsSocialDiscoveryWorker).to have_received(:perform_async).with(campaign.id)
  end

  it 'triggers when the comment already exists and the 10th useful reaction arrives after' do
    comment!(create_user('commenter@example.com'))
    react_useful_n_times(10)

    expect(NewsSocialDiscoveryCampaign.count).to eq(1)
  end

  it 'does not create a second campaign for the 11th useful reaction' do
    react_useful_n_times(10)
    comment!(create_user('commenter@example.com'))

    react_useful!(create_user('extra@example.com'))

    expect(NewsSocialDiscoveryCampaign.count).to eq(1)
    expect(NewsSocialDiscoveryWorker).to have_received(:perform_async).once
  end

  it 'does not create a second campaign when a reaction is removed and re-added' do
    user = create_user('flaky@example.com')
    react_useful_n_times(9)
    comment!(create_user('commenter@example.com'))

    # false -> true es un UPDATE sobre una fila persistida (no un INSERT) --
    # ejercita justo el caso que after_create solo (sin after_save) se
    # perderia.
    reaction = NewsFeedReaction.create!(user: user, news_feed: news_feed, useful: false)
    reaction.update!(useful: true)
    reaction.update!(useful: false)
    reaction.update!(useful: true)

    expect(NewsSocialDiscoveryCampaign.count).to eq(1)
    expect(NewsSocialDiscoveryWorker).to have_received(:perform_async).once
  end

  it 'does not trigger for a news_feed older than 30 days' do
    news_feed.update_column(:created_at, 31.days.ago)

    react_useful_n_times(10)
    comment!(create_user('commenter@example.com'))

    expect(NewsSocialDiscoveryCampaign.count).to eq(0)
  end

  it 'triggers exactly at the 30-day boundary' do
    news_feed.update_column(:created_at, 30.days.ago)

    react_useful_n_times(10)
    comment!(create_user('commenter@example.com'))

    expect(NewsSocialDiscoveryCampaign.count).to eq(1)
  end

  it 'does not create a duplicate campaign under a concurrent claim attempt' do
    react_useful_n_times(10)
    comment!(create_user('commenter@example.com'))

    expect(NewsSocialDiscoveryCampaign.count).to eq(1)

    # Simula un segundo hook evaluando casi al mismo tiempo, contra el
    # mismo estado ya trigger-eado -- el indice unico de la migracion, no
    # un SELECT previo, es lo que realmente lo frena.
    described_class.evaluate(news_feed)

    expect(NewsSocialDiscoveryCampaign.count).to eq(1)
    expect(NewsSocialDiscoveryWorker).to have_received(:perform_async).once
  end
end
