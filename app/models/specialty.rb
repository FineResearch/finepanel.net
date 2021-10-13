# == Schema Information
#
# Table name: activity_feeds
#
#  id                :integer          not null, primary key
#  name              :string(255)
#  slug              :string(255)
#  created_at        :datetime
#  updated_at        :updated_at

class Specialty < ApplicationRecord
  # -- Associations --
  has_many :articles, dependent: :destroy
  has_many :news_feeds, dependent: :destroy

  # -- Vaidations --
  validates :name, presence: true
  validates :slug, uniqueness: true
end
