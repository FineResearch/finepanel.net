require 'rails_helper'

RSpec.describe NewsFeedReaction, type: :model do
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

  it 'is valid with a boolean useful value' do
    reaction = NewsFeedReaction.new(user: user, news_feed: news_feed, useful: true)

    expect(reaction).to be_valid
  end

  it 'allows a single reaction per user and news_feed' do
    NewsFeedReaction.create!(user: user, news_feed: news_feed, useful: true)
    duplicate = NewsFeedReaction.new(user: user, news_feed: news_feed, useful: false)

    expect(duplicate).not_to be_valid
    expect do
      duplicate.save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
