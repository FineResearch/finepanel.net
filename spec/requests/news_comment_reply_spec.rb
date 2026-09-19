require 'rails_helper'

RSpec.describe 'POST /api/v1/news_comment/:id/reply', type: :request do
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
  let(:replier) { User.create!(encrypted_email: Digest::MD5.hexdigest('replier@example.com'), jti: SecureRandom.uuid) }
  let(:comment) do
    NewsComment.create!(
      text: 'comentario de prueba',
      user: author,
      news_feed: news_feed,
      user_info: { 'email' => 'author@example.com', 'complete_name' => 'Autor Test' },
    )
  end

  # Mismo criterio que news_comment_reactions_spec.rb: check_basic_auth
  # decodifica el JWT sin verificar firma, alcanza con un token sin firmar.
  def auth_headers(for_user)
    token = JWT.encode({ 'jti' => for_user.jti }, nil, 'none')
    { 'Authorization' => "Bearer #{token}" }
  end

  before do
    allow(CommentReplyNotificationWorker).to receive(:perform_async)
  end

  it 'requires authentication' do
    post reply_api_v1_news_comment_path(comment)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates a reply to a top-level comment' do
    post reply_api_v1_news_comment_path(comment),
      params: { text: 'una respuesta', complete_name: 'Dr. Replier', country: 'Argentina', specialty: '25' },
      headers: auth_headers(replier)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['parentCommentId']).to eq(comment.id)
    expect(body['text']).to eq('una respuesta')

    reply = NewsComment.find(body['id'])
    expect(reply.news_feed_id).to eq(news_feed.id)
    expect(reply.parent_comment_id).to eq(comment.id)
  end

  it 'allows replying to your own comment' do
    post reply_api_v1_news_comment_path(comment),
      params: { text: 'me respondo a mi mismo' },
      headers: auth_headers(author)

    expect(response).to have_http_status(:ok)
  end

  it 'rejects replying to a reply (only 1 level of nesting)' do
    reply = NewsComment.create!(
      text: 'primera respuesta',
      user: replier,
      news_feed: news_feed,
      user_info: { 'email' => 'replier@example.com' },
      parent_comment: comment,
    )

    post reply_api_v1_news_comment_path(reply),
      params: { text: 'respuesta a una respuesta' },
      headers: auth_headers(author)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'returns 404 for a non-existent parent comment' do
    post reply_api_v1_news_comment_path(id: 0),
      params: { text: 'una respuesta' },
      headers: auth_headers(replier)

    expect(response).to have_http_status(:not_found)
  end
end
