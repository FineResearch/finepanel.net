# frozen_string_literal: true

# Centraliza las 4 condiciones de disparo de la campana de "descubrimiento
# social" (A: >=10 utiles distintos, B: >=1 comentario, C: publicado hace
# <=30 dias segun la fecha propia de Fine (created_at), D: nunca disparado
# antes) y la reserva atomica de la campana. Se llama de forma
# sincrona/inline desde ambos hooks posibles (NewsFeedReaction#after_save,
# NewsComment#after_create) -- las queries de conteo son baratas
# (COUNT/EXISTS por news_feed_id, ya indexado), y la reserva real de
# "nunca disparado antes" es el indice unico de DB en
# news_social_discovery_campaigns.news_feed_id (create! + rescue), no un
# SELECT previo -- evita el race de 2 hooks concurrentes viendo ambos
# "todavia no existe" e intentando crear la campana los dos.
class NewsSocialDiscoveryService
  MIN_USEFUL_REACTIONS = 10
  RECENCY_WINDOW = 30.days

  def self.evaluate(news_feed)
    new(news_feed).evaluate
  end

  def initialize(news_feed)
    @news_feed = news_feed
  end

  def evaluate
    return unless news_feed.present?
    return unless recent_enough?
    return unless has_comment?

    useful_count = useful_reaction_count
    return unless useful_count >= MIN_USEFUL_REACTIONS

    claim_campaign(useful_count)
  end

  private

  attr_reader :news_feed

  def recent_enough?
    news_feed.created_at.present? && news_feed.created_at >= RECENCY_WINDOW.ago
  end

  def has_comment?
    news_feed.news_comments.exists?
  end

  # NewsFeedReaction tiene un indice unico en [user_id, news_feed_id], asi
  # que where(useful: true).count ya es un conteo de usuarios distintos --
  # no hace falta .distinct.
  def useful_reaction_count
    news_feed.news_feed_reactions.where(useful: true).count
  end

  def claim_campaign(useful_count)
    campaign = NewsSocialDiscoveryCampaign.create!(
      news_feed_id: news_feed.id,
      triggered_at: Time.current,
      useful_count_at_trigger: useful_count,
      comment_count_at_trigger: news_feed.news_comments.count,
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  else
    NewsSocialDiscoveryWorker.perform_async(campaign.id)
  end
end
