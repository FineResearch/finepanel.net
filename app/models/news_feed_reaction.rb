# frozen_string_literal: true
class NewsFeedReaction < ApplicationRecord
  belongs_to :user
  belongs_to :news_feed

  validates :useful, inclusion: { in: [true, false] }
  validates :user_id, uniqueness: { scope: :news_feed_id }
end
