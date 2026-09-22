# frozen_string_literal: true

class NewsSocialDiscoveryCampaign < ApplicationRecord
  # -- Associations --
  belongs_to :news_feed

  # -- Validations --
  validates :news_feed_id, uniqueness: true
  validates :triggered_at, :useful_count_at_trigger, :comment_count_at_trigger, presence: true
end
