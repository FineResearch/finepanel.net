# frozen_string_literal: true

class NewsFeedView < ApplicationRecord
  # -- Associations --
  belongs_to :user
  belongs_to :news_feed
  belongs_to :specialty, optional: true

  # -- Validations --
  validates :user_id, uniqueness: { scope: :news_feed_id }
end
