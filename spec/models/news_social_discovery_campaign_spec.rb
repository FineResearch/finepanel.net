require 'rails_helper'

RSpec.describe NewsSocialDiscoveryCampaign, type: :model do
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

  it 'is valid with the required trigger snapshot fields' do
    campaign = NewsSocialDiscoveryCampaign.new(
      news_feed: news_feed,
      triggered_at: Time.current,
      useful_count_at_trigger: 10,
      comment_count_at_trigger: 1,
    )

    expect(campaign).to be_valid
  end

  it 'allows a single campaign per news_feed' do
    NewsSocialDiscoveryCampaign.create!(
      news_feed: news_feed, triggered_at: Time.current, useful_count_at_trigger: 10, comment_count_at_trigger: 1,
    )
    duplicate = NewsSocialDiscoveryCampaign.new(
      news_feed: news_feed, triggered_at: Time.current, useful_count_at_trigger: 11, comment_count_at_trigger: 2,
    )

    expect(duplicate).not_to be_valid
    expect do
      duplicate.save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
