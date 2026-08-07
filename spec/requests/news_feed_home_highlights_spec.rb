require 'rails_helper'

RSpec.describe 'GET /api/v1/news_feed/home_highlights', type: :request do
  def create_specialty(slug, name = slug.titleize)
    Specialty.create!(name: name, slug: slug)
  end

  def create_article(specialty)
    Article.create!(
      dynamed_id: "DM-#{SecureRandom.hex(4)}",
      title: 'Articulo de prueba',
      slug: "/topics/test-#{SecureRandom.hex(4)}",
      specialty: specialty,
    )
  end

  def create_news_feed(specialty, fine_news_summary:, alert_created_at: Time.current)
    NewsFeed.create!(
      text: "texto #{SecureRandom.hex(4)}",
      specialty: specialty,
      article: create_article(specialty),
      alert_created_at: alert_created_at,
      fine_news_summary: fine_news_summary,
    )
  end

  def summary_for(title, evidence_source = 'Annals of Oncology')
    {
      'editorial_content' => { 'title' => title },
      'article_metadata' => { 'evidence_source' => evidence_source },
    }
  end

  it 'works without an Authorization header' do
    get home_highlights_api_v1_news_feed_index_path

    expect(response).to have_http_status(:ok)
  end

  it 'returns only the highlighted specialties that have a fine_news_summary update, in the fixed order' do
    oncology = create_specialty('oncology', 'Oncologia')
    cardiology = create_specialty('cardiology', 'Cardiologia')
    unrelated = create_specialty('urology', 'Urologia')

    create_news_feed(cardiology, fine_news_summary: summary_for('Novedad de cardiologia'))
    create_news_feed(oncology, fine_news_summary: summary_for('Novedad de oncologia'))
    create_news_feed(unrelated, fine_news_summary: summary_for('Novedad de urologia'))

    get home_highlights_api_v1_news_feed_index_path

    body = JSON.parse(response.body)
    slugs = body.map { |item| item['specialtySlug'] }

    expect(slugs).to eq(%w[oncology cardiology])
  end

  it 'skips a specialty when its most recent update has no fine_news_summary' do
    oncology = create_specialty('oncology', 'Oncologia')

    create_news_feed(oncology, fine_news_summary: summary_for('Vieja con resumen'), alert_created_at: 2.days.ago)
    create_news_feed(oncology, fine_news_summary: nil, alert_created_at: 1.day.ago)

    get home_highlights_api_v1_news_feed_index_path

    body = JSON.parse(response.body)

    expect(body).to be_empty
  end

  it 'picks the most recent fine_news_summary update for the specialty' do
    oncology = create_specialty('oncology', 'Oncologia')

    create_news_feed(oncology, fine_news_summary: summary_for('Vieja'), alert_created_at: 2.days.ago)
    create_news_feed(oncology, fine_news_summary: summary_for('Nueva'), alert_created_at: 1.day.ago)

    get home_highlights_api_v1_news_feed_index_path

    body = JSON.parse(response.body)

    expect(body.first['title']).to eq('Nueva')
  end

  it 'only exposes the public-safe fields' do
    oncology = create_specialty('oncology', 'Oncologia')
    create_news_feed(oncology, fine_news_summary: summary_for('Novedad', 'Annals of Oncology'))

    get home_highlights_api_v1_news_feed_index_path

    body = JSON.parse(response.body)

    expect(body.first.keys).to match_array(
      %w[id specialtySlug specialtyName title evidenceSource],
    )
    expect(body.first['evidenceSource']).to eq('Annals of Oncology')
  end
end
