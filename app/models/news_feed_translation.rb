# frozen_string_literal: true
# == Schema Information
#
# Table name: news_feed_translations
#
#  id                :integer          not null, primary key
#  news_feed_id      :integer
#  locale            :integer
#  title             :sting
#  text              :text
#  created_at        :datetime
#  updated_at        :updated_at

class NewsFeedTranslation < ApplicationRecord

  # -- Associations --
  belongs_to :news_feed

  # -- Vaidations --
  validates :text, :title, presence: true
  validates_uniqueness_of :locale, scope: [:news_feed_id]

  enum locale: [:es, :pt]
end
