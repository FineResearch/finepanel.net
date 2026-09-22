require 'rails_helper'

RSpec.describe 'POST /api/v1/news_feed/:id/increment_view_count', type: :request do
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

  # Mismo criterio que news_feed_reactions_spec.rb: check_basic_auth
  # decodifica el JWT sin verificar firma, alcanza con un token sin firmar.
  def auth_headers(for_user)
    token = JWT.encode({ 'jti' => for_user.jti }, nil, 'none')
    { 'Authorization' => "Bearer #{token}" }
  end

  it 'increments view_count and records an identified view with the resolved specialty' do
    post increment_view_count_api_v1_news_feed_path(news_feed),
      params: { email: 'a@example.com', specialty: specialty.slug },
      headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(news_feed.reload.view_count).to eq(1)

    view = NewsFeedView.find_by(user: user, news_feed: news_feed)
    expect(view).to be_present
    expect(view.specialty).to eq(specialty)
    expect(view.email).to eq('a@example.com')
  end

  it 'does not duplicate the view row on a second call from the same user' do
    post increment_view_count_api_v1_news_feed_path(news_feed),
      params: { email: 'a@example.com', specialty: specialty.slug },
      headers: auth_headers(user)
    post increment_view_count_api_v1_news_feed_path(news_feed),
      params: { email: 'a@example.com', specialty: specialty.slug },
      headers: auth_headers(user)

    expect(news_feed.reload.view_count).to eq(2)
    expect(NewsFeedView.where(user: user, news_feed: news_feed).count).to eq(1)
  end

  it 'still succeeds and increments view_count when the specialty slug does not resolve' do
    post increment_view_count_api_v1_news_feed_path(news_feed),
      params: { email: 'a@example.com', specialty: 'unknown-slug' },
      headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    view = NewsFeedView.find_by(user: user, news_feed: news_feed)
    expect(view.specialty_id).to be_nil
  end
end
