require 'rails_helper'

RSpec.describe NewsFeedView, type: :model do
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
  let(:user) { User.create!(encrypted_email: Digest::MD5.hexdigest('a@example.com'), jti: SecureRandom.uuid) }

  it 'is valid with a specialty' do
    view = NewsFeedView.new(user: user, news_feed: news_feed, specialty: specialty, email: 'a@example.com')

    expect(view).to be_valid
  end

  it 'is valid without a specialty (slug that did not resolve)' do
    view = NewsFeedView.new(user: user, news_feed: news_feed, specialty: nil)

    expect(view).to be_valid
  end

  it 'allows a single view per user and news_feed' do
    NewsFeedView.create!(user: user, news_feed: news_feed)
    duplicate = NewsFeedView.new(user: user, news_feed: news_feed)

    expect(duplicate).not_to be_valid
    expect do
      duplicate.save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
