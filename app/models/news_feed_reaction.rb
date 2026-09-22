# frozen_string_literal: true
class NewsFeedReaction < ApplicationRecord
  belongs_to :user
  belongs_to :news_feed

  validates :useful, inclusion: { in: [true, false] }
  validates :user_id, uniqueness: { scope: :news_feed_id }

  # after_save, no after_create: por el toggle de NewsFeedController#react
  # (find_or_initialize_by + save!), pasar de useful:false a useful:true es
  # un UPDATE sobre una fila ya persistida, no un INSERT -- after_create
  # solo se perderia justo esa transicion.
  after_save :evaluate_social_discovery, if: :useful?

  def evaluate_social_discovery
    NewsSocialDiscoveryService.evaluate(news_feed)
  end
end
