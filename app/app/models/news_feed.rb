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

  DYNAMED_HOST = "https://www.dynamed.com"

  # -- Vaidations --
  validates :text, presence: true

  # -- Callbacks --
  after_create :set_link

  def set_link
    self.update_column('link', "#{DYNAMED_HOST}#{self.article.slug}##{self.anchor}")
  end

  def newsfeed_type
    return 'No Type' unless self.article.present?
    type = self.article.slug[/#{'/'}(.*?)#{'/'}/m, 1]
    type.present? ? type.upcase : 'No Type'
  end

  def set_text
    self.text.camelcase
  end

  def set_alert_date
    return ' ' unless self.alert_created_at.present?
    self.alert_created_at.strftime("%d/%m/%Y")
  end

  def set_time_tag(locale = nil)
    if locale.present?
      self.alert_created_at > 3.months.ago ? I18n.with_locale(locale) { I18n.t("newsfeed.new")} : ''
    else
      self.alert_created_at > 3.months.ago ? 'NUEVA' : ''
    end
  end
end
