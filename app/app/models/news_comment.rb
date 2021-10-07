# frozen_string_literal: true
# == Schema Information
#
# Table name: news_comments
#
#  id                :integer          not null, primary key
#  text              :string
#  user_id           :integer
#  news_feed_id      :integer
#  user_info         :jsonb
#  created_at        :datetime
#  updated_at        :updated_at

class NewsComment < ApplicationRecord

  # -- Associations --
  belongs_to :user
  belongs_to :news_feed

  # -- Vaidations --
  validates :text, presence: true
end
