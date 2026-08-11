require 'rails_helper'

RSpec.describe TranslateApi::TranslateFineNewsSummary do
  let(:fine_news_summary) do
    {
      "article_metadata" => {
        "article_category" => "Drug safety",
        "evidence_source" => "FDA Product Information, July 2026",
        "suggested_image" => "safety-1"
      },
      "editorial_content" => {
        "title" => "Some title",
        "reading_cta" => "Read more",
        "what_this_evidence_shows" => "Shows something",
        "what_is_new" => "Something new",
        "clinical_implications" => "Some implications",
        "limitations_and_precautions" => "Some limitations"
      },
      "community_discussion" => {
        "question" => "What do you think?"
      }
    }
  end

  let(:specialty) { Specialty.create!(name: 'Test', slug: "test-#{SecureRandom.hex(4)}") }
  let(:article) do
    Article.create!(
      dynamed_id: "DM-#{SecureRandom.hex(4)}",
      title: 'T',
      slug: "/t/#{SecureRandom.hex(4)}",
      specialty: specialty
    )
  end
  let(:news_feed) do
    NewsFeed.create!(
      text: 'texto',
      specialty: specialty,
      article: article,
      fine_news_summary: fine_news_summary
    )
  end

  let(:fake_translate_client) do
    instance_double(Google::Cloud::Translate::V2::Api).tap do |client|
      allow(client).to receive(:translate) do |text, to:|
        double(text: "[#{to}] #{text}")
      end
    end
  end

  before do
    allow_any_instance_of(described_class).to receive(:translate_client).and_return(fake_translate_client)
  end

  describe '#process' do
    it 'carries suggested_image through unchanged for every locale, without translating it' do
      described_class.new(news_feed.id).process

      translations = news_feed.reload.fine_news_summary_translations

      expect(translations['es']['article_metadata']['suggested_image']).to eq('safety-1')
      expect(translations['pt']['article_metadata']['suggested_image']).to eq('safety-1')
    end

    it 'still translates the fields that should be translated' do
      described_class.new(news_feed.id).process

      translations = news_feed.reload.fine_news_summary_translations

      expect(translations['es']['article_metadata']['article_category']).to eq('[es] Drug safety')
      expect(translations['es']['editorial_content']['title']).to eq('[es] Some title')
    end

    it 'leaves suggested_image absent when the original summary has none' do
      fine_news_summary['article_metadata'].delete('suggested_image')
      news_feed.update!(fine_news_summary: fine_news_summary)

      described_class.new(news_feed.id).process

      translations = news_feed.reload.fine_news_summary_translations

      expect(translations['es']['article_metadata']['suggested_image']).to be_nil
    end
  end
end
