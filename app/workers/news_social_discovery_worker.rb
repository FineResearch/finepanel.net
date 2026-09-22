# frozen_string_literal: true

# Calcula la audiencia elegible para una campana ya reservada
# (NewsSocialDiscoveryService la crea, este worker solo la ejecuta) y
# manda el aviso con el mismo patron reserva-antes-de-mandar que usan los
# otros 4 workers de notificaciones (Notification.create! + rescue antes
# de encolar el mail -- el indice unico parcial de la migracion
# 20260921090200 es la proteccion real bajo concurrencia/reintentos, no
# este chequeo).
class NewsSocialDiscoveryWorker
  include Sidekiq::Worker
  # Campana puntual y conservadora -- no tiene sentido el default de
  # Sidekiq (~25 reintentos a lo largo de semanas) si algo esta
  # sistematicamente roto (ej. SENDGRID_API_KEY invalida).
  sidekiq_options retry: 5

  NOTIFICATION_TYPE = Notification::TYPES[:news_social_discovery]
  COOLDOWN_WINDOW = 30.days

  def perform(campaign_id)
    campaign = NewsSocialDiscoveryCampaign.find_by(id: campaign_id)
    return unless campaign.present?

    news_feed = campaign.news_feed
    return unless news_feed.present?

    candidates = eligible_candidates(news_feed)
    candidates.each { |candidate| send_notification(candidate, news_feed, campaign) }

    # recipient_count se recalcula siempre por COUNT real contra
    # Notification (nunca se acumula en Ruby) -- converge al numero
    # correcto sin importar cuantos reintentos de Sidekiq hicieron falta.
    campaign.update!(
      eligible_recipient_count: candidates.size,
      recipient_count: Notification.where(news_feed_id: news_feed.id, notification_type: NOTIFICATION_TYPE).count,
    )
  end

  private

  # Cada fila de NewsFeedView ya trae la especialidad del LECTOR (no la
  # del articulo), consistente en todas sus vistas -- por eso este unico
  # where ya responde a la vez "pertenece a la base de lectores" y "misma
  # especialidad que la noticia".
  #
  # .where.not(user_id: nil) en ambas subqueries es por las dudas: un NOT
  # IN con algun NULL adentro hace que Postgres no excluya a nadie (logica
  # de 3 valores), y ninguna de las 2 columnas tiene NOT NULL a nivel de
  # esquema, solo a nivel de validacion de modelo.
  def eligible_candidates(news_feed)
    already_read = NewsFeedView.where(news_feed_id: news_feed.id).where.not(user_id: nil).select(:user_id)
    cooldown = Notification
      .where(notification_type: NOTIFICATION_TYPE)
      .where('created_at >= ?', COOLDOWN_WINDOW.ago)
      .where.not(user_id: nil)
      .select(:user_id)

    NewsFeedView
      .select('DISTINCT ON (news_feed_views.user_id) news_feed_views.user_id, news_feed_views.email')
      .joins(:user)
      .where(specialty_id: news_feed.specialty_id)
      .where(users: { comment_notifications_opt_out: false })
      .where.not(user_id: already_read)
      .where.not(user_id: cooldown)
      .order('news_feed_views.user_id, news_feed_views.created_at DESC')
      .to_a
  end

  def send_notification(candidate, news_feed, campaign)
    user = User.find_by(id: candidate.user_id)
    return unless user.present?

    begin
      Notification.create!(
        user_id: candidate.user_id,
        news_feed_id: news_feed.id,
        notification_type: NOTIFICATION_TYPE,
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      return
    end

    return unless candidate.email.present?

    locale = resolve_locale(user)

    NewsConversationReminderMailer.news_social_discovery_email(
      candidate.email,
      locale,
      news_feed,
      user,
      campaign.useful_count_at_trigger,
    ).deliver_later
  end

  def resolve_locale(user)
    return 'es' unless user.present?

    user.language == 'por' ? 'pt' : 'es'
  end
end
