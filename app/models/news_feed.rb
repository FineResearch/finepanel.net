# == Schema Information
#
# Table name: activity_feeds
#
#  id                :integer          not null, primary key
#  text              :text
#  link              :string(255)
#  anchor            :string(255)
#  alert_created_at  :datetime
#  update_type       :string
#  update_priority   :string
#  specialty_id      :integer
#  article_id        :integer
#  title             :string
#  translated_text   :hstore
#  translated_title  :hstore
#  created_at        :datetime
#  updated_at        :updated_at

class NewsFeed < ApplicationRecord
  # -- Associations --
  belongs_to :specialty
  belongs_to :article
  has_many :news_comments, dependent: :destroy
  has_many :news_feed_translations, dependent: :destroy

  DYNAMED_HOST = "https://www.dynamed.com"
  AVAILABLE_LOCALS = %w{es pt}
  MAXIMUM_NEWS_BY_SPECIALTY = 20

  # -- Vaidations --
  validates :text, presence: true
  validates_uniqueness_of :text

  # -- Callbacks --
  after_create :set_link
  after_create :set_title

  # -- Scopes --
  scope :search_by_text, -> (query) {joins(:news_feed_translations).where("news_feed_translations.text LIKE ?", "%#{query}%") }
  scope :search_by_title, -> (query) {joins(:news_feed_translations).where("news_feed_translations.title LIKE ?", "%#{query}%")}

  def set_link
    self.update_column('link', "#{DYNAMED_HOST}#{self.article.slug}##{self.anchor}")
  end

  def set_title
    self.update_column('title', self.article.title)
  end

  def get_news_type
    self.article.slug[/#{'/'}(.*?)#{'/'}/m, 1]
  end
end
