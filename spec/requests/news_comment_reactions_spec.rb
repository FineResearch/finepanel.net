require 'rails_helper'

RSpec.describe 'POST /api/v1/news_comment/:id/react', type: :request do
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
  let(:author) { User.create!(encrypted_email: Digest::MD5.hexdigest('author@example.com'), jti: SecureRandom.uuid) }
  let(:reactor) { User.create!(encrypted_email: Digest::MD5.hexdigest('reactor@example.com'), jti: SecureRandom.uuid) }
  let(:comment) do
    NewsComment.create!(
      text: 'comentario de prueba',
      user: author,
      news_feed: news_feed,
      user_info: { 'email' => 'author@example.com', 'complete_name' => 'Autor Test' },
    )
  end

  # Mismo criterio que news_feed_reactions_spec.rb: check_basic_auth decodifica
  # el JWT sin verificar firma, alcanza con un token sin firmar para los tests.
  def auth_headers(for_user)
    token = JWT.encode({ 'jti' => for_user.jti }, nil, 'none')
    { 'Authorization' => "Bearer #{token}" }
  end

  before do
    allow(CommentAgreementNotificationWorker).to receive(:perform_async)
  end

  it 'requires authentication' do
    post react_api_v1_news_comment_path(comment)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates a reaction on first click and returns the updated count' do
    post react_api_v1_news_comment_path(comment),
      params: { complete_name: 'Dra. Reactor', country: 'Argentina', specialty: '25' },
      headers: auth_headers(reactor)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['myReaction']).to eq(true)
    expect(body['reactionCount']).to eq(1)
    expect(NewsCommentReaction.where(user: reactor, news_comment: comment).count).to eq(1)
  end

  it 'removes the reaction on the second click (toggle off)' do
    post react_api_v1_news_comment_path(comment), headers: auth_headers(reactor)
    post react_api_v1_news_comment_path(comment), headers: auth_headers(reactor)

    body = JSON.parse(response.body)
    expect(body['myReaction']).to eq(false)
    expect(body['reactionCount']).to eq(0)
    expect(NewsCommentReaction.where(user: reactor, news_comment: comment).count).to eq(0)
  end

  it 'returns 422 when trying to react to your own comment' do
    post react_api_v1_news_comment_path(comment), headers: auth_headers(author)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(NewsCommentReaction.count).to eq(0)
  end

  it 'counts distinct reactors only, not per-request' do
    other_reactor = User.create!(encrypted_email: Digest::MD5.hexdigest('other@example.com'), jti: SecureRandom.uuid)

    post react_api_v1_news_comment_path(comment), headers: auth_headers(reactor)
    post react_api_v1_news_comment_path(comment), headers: auth_headers(other_reactor)

    body = JSON.parse(response.body)
    expect(body['reactionCount']).to eq(2)
  end
end

RSpec.describe 'GET /api/v1/news_comment/:id/reactors', type: :request do
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
  let(:author) { User.create!(encrypted_email: Digest::MD5.hexdigest('author@example.com'), jti: SecureRandom.uuid) }
  let(:reactor) { User.create!(encrypted_email: Digest::MD5.hexdigest('reactor@example.com'), jti: SecureRandom.uuid) }
  let(:comment) do
    NewsComment.create!(
      text: 'comentario de prueba',
      user: author,
      news_feed: news_feed,
      user_info: { 'email' => 'author@example.com', 'complete_name' => 'Autor Test' },
    )
  end

  def auth_headers(for_user)
    token = JWT.encode({ 'jti' => for_user.jti }, nil, 'none')
    { 'Authorization' => "Bearer #{token}" }
  end

  it 'lists name/specialty/country for each reactor without exposing email' do
    NewsCommentReaction.create!(
      user: reactor,
      news_comment: comment,
      user_info: { 'email' => 'reactor@example.com', 'complete_name' => 'Dra. Reactor', 'specialty' => '25', 'country' => 'Argentina' },
    )

    get reactors_api_v1_news_comment_path(comment), headers: auth_headers(author)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.length).to eq(1)
    expect(body.first['complete_name']).to eq('Dra. Reactor')
    expect(body.first).not_to have_key('email')
  end
end
