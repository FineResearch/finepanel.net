require 'rails_helper'

RSpec.describe 'POST /api/v1/news_feed/:id/react', type: :request do
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

  # `check_basic_auth` decodifica el JWT sin verificar firma (JWT.decode(token, nil, false))
  # y resuelve el usuario por `jti`, asi que alcanza con un token sin firmar para los tests.
  def auth_headers(for_user)
    token = JWT.encode({ 'jti' => for_user.jti }, nil, 'none')
    { 'Authorization' => "Bearer #{token}" }
  end

  it 'requires authentication' do
    post react_api_v1_news_feed_path(news_feed), params: { useful: true }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates a reaction and returns the updated count' do
    post react_api_v1_news_feed_path(news_feed), params: { useful: true }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['myReaction']).to eq(true)
    expect(body['usefulCount']).to eq(1)
    expect(NewsFeedReaction.where(user: user, news_feed: news_feed, useful: true).count).to eq(1)
  end

  it 'switches the reaction when the user picks the other option' do
    post react_api_v1_news_feed_path(news_feed), params: { useful: true }, headers: auth_headers(user)
    post react_api_v1_news_feed_path(news_feed), params: { useful: false }, headers: auth_headers(user)

    body = JSON.parse(response.body)
    expect(body['myReaction']).to eq(false)
    expect(body['usefulCount']).to eq(0)
    expect(NewsFeedReaction.where(user: user, news_feed: news_feed).count).to eq(1)
  end

  it 'removes the reaction when the user picks the same option again' do
    post react_api_v1_news_feed_path(news_feed), params: { useful: true }, headers: auth_headers(user)
    post react_api_v1_news_feed_path(news_feed), params: { useful: true }, headers: auth_headers(user)

    body = JSON.parse(response.body)
    expect(body['myReaction']).to be_nil
    expect(body['usefulCount']).to eq(0)
    expect(NewsFeedReaction.where(user: user, news_feed: news_feed).count).to eq(0)
  end

  it 'only counts "useful" reactions from other users towards usefulCount' do
    other_user = User.create!(encrypted_email: Digest::MD5.hexdigest('b@example.com'), jti: SecureRandom.uuid)

    post react_api_v1_news_feed_path(news_feed), params: { useful: true }, headers: auth_headers(user)
    post react_api_v1_news_feed_path(news_feed), params: { useful: false }, headers: auth_headers(other_user)

    body = JSON.parse(response.body)
    expect(body['usefulCount']).to eq(1)
  end
end
