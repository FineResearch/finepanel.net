# == Schema Information
#
# Table name: activity_feeds
#
#  id                :integer          not null, primary key
#  dynamed_id        :string(255)
#  title             :string(255)
#  slug              :string(255)
#  specialty_id      :integer
#  created_at        :datetime
#  updated_at        :updated_at

class Article < ApplicationRecord
  # -- Associations --
  belongs_to :specialty
  has_many   :news_feeds, dependent: :destroy

  # -- Vaidations --
  validates :dynamed_id, presence: true, uniqueness: true
  validates :title, presence: true
  validates :slug, presence: true
end
