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
#  created_at        :datetime
#  updated_at        :updated_at

class NewsFeed < ApplicationRecord
  # -- Associations --
  belongs_to :specialty
  belongs_to :article
  has_many :news_comments, dependent: :destroy

  DYNAMED_HOST = "https://www.dynamed.com"

  # -- Vaidations --
  validates :text, presence: true

  # -- Callbacks --
  after_create :set_link

  # -- Scopes --
  scope :search_by_text, -> (query) { where("text LIKE ?", "%#{query}%") }
  scope :search_by_title, -> (query) {joins(:article).where("articles.title LIKE ?", "%#{query}%")}

  def set_link
    self.update_column('link', "#{DYNAMED_HOST}#{self.article.slug}##{self.anchor}")
  end

  def get_news_type
    self.article.slug[/#{'/'}(.*?)#{'/'}/m, 1]
  end
end
