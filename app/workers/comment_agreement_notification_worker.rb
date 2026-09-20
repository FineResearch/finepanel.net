# frozen_string_literal: true

# Notifica al autor de un comentario cuando 2 colegas distintos reaccionaron
# "Concordo"/"De acuerdo" a ese comentario puntual. Un solo envio por
# comentario, para siempre (si despues baja de 2 y vuelve a subir, no se
# reenvia -- ver NewsCommentReaction#check_agreement_threshold, que solo
# encola esto la primera vez que el conteo cruza a 2, y el chequeo
# already_notified? de aca abajo, que es la reserva real via el indice
# unico de notifications).
class CommentAgreementNotificationWorker
  include Sidekiq::Worker

  NOTIFICATION_TYPE = Notification::TYPES[:comment_agreement]

  def perform(news_comment_id)
    comment = NewsComment.find_by(id: news_comment_id)
    return unless comment.present?
    return if already_notified?(comment)

    send_notification(comment)
  end

  private

  def already_notified?(comment)
    Notification.exists?(
      user_id: comment.user_id,
      news_feed_id: comment.news_feed_id,
      notification_type: NOTIFICATION_TYPE,
      news_comment_id: comment.id,
    )
  end

  # Reserva la notificacion primero (misma logica que
  # FirstCommentReplyWorker/NewsCommentReminderWorker -- el indice unico de
  # DB protege ante dos jobs en simultaneo) y recien despues manda el mail.
  def send_notification(comment)
    begin
      Notification.create!(
        user_id: comment.user_id,
        news_feed_id: comment.news_feed_id,
        notification_type: NOTIFICATION_TYPE,
        news_comment_id: comment.id,
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      return
    end

    return unless comment.user_info.present? && comment.user_info['email'].present?

    user = comment.user
    locale = resolve_locale(user)

    NewsConversationReminderMailer.comment_agreement_email(
      comment.user_info['email'],
      locale,
      comment.news_feed,
      user,
    ).deliver_later
  end

  def resolve_locale(user)
    return 'es' unless user.present?

    user.language == 'por' ? 'pt' : 'es'
  end
end
