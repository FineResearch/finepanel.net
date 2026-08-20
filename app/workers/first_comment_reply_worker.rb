# Notifica al autor del primer comentario de una noticia cuando llega el
# segundo comentario (de otro colega). Un solo envio por usuario/noticia,
# separado del reminder de reactivacion (NewsCommentReminderWorker), que
# sigue funcionando sin cambios para su propio disparador (3+ comentarios
# subsiguientes de 2+ autores distintos).
class FirstCommentReplyWorker
  include Sidekiq::Worker

  NOTIFICATION_TYPE = Notification::TYPES[:first_comment_reply]

  def perform(news_feed_id)
    news_feed = NewsFeed.find_by(id: news_feed_id)
    return unless news_feed.present?

    comments = news_feed.news_comments.order(:created_at).to_a
    # No depende solo de que el modelo lo encole en el momento correcto:
    # si por algun motivo el worker corre con un unico comentario todavia
    # (ej. un retry de Sidekiq despues de un cambio de estado), no hay a
    # quien avisar todavia.
    return if comments.size < 2

    first_comment = comments.first
    return if already_notified?(first_comment.user_id, news_feed_id)

    send_notification(first_comment, news_feed)
  end

  private

  def already_notified?(user_id, news_feed_id)
    Notification.exists?(
      user_id: user_id,
      news_feed_id: news_feed_id,
      notification_type: NOTIFICATION_TYPE,
    )
  end

  # Reserva la notificacion primero (la unicidad a nivel DB protege contra
  # el caso de dos jobs corriendo en simultaneo para la misma noticia) y
  # recien despues encola el mail, para nunca enviar dos veces al mismo
  # usuario aunque el registro de la notificacion falle por alguna razon.
  def send_notification(first_comment, news_feed)
    begin
      Notification.create!(
        user_id: first_comment.user_id,
        news_feed_id: news_feed.id,
        notification_type: NOTIFICATION_TYPE,
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      return
    end

    return unless first_comment.user_info.present? && first_comment.user_info['email'].present?

    locale = resolve_locale(first_comment.user_id)

    NewsConversationReminderMailer.first_reply_email(
      first_comment.user_info['email'],
      locale,
      news_feed,
    ).deliver_later
  end

  def resolve_locale(user_id)
    user = User.find_by(id: user_id)
    return 'es' unless user.present?

    user.language == 'por' ? 'pt' : 'es'
  end
end
