# frozen_string_literal: true

# Notifica al autor de un comentario cuando otro colega le responde
# directamente (NewsComment#parent_comment_id). Un solo envio por
# comentario, para siempre -- si se acumulan mas respuestas despues de la
# primera, no se vuelve a notificar (ver already_notified? mas abajo, la
# reserva real es el indice unico de notifications, igual que en
# CommentAgreementNotificationWorker/FirstCommentReplyWorker). No notifica
# si el autor se responde a si mismo.
class CommentReplyNotificationWorker
  include Sidekiq::Worker

  NOTIFICATION_TYPE = Notification::TYPES[:comment_reply]

  def perform(reply_id)
    reply = NewsComment.find_by(id: reply_id)
    return unless reply.present? && reply.parent_comment.present?

    parent_comment = reply.parent_comment
    return if parent_comment.user_id == reply.user_id
    return if already_notified?(parent_comment)

    send_notification(parent_comment, reply)
  end

  private

  def already_notified?(parent_comment)
    Notification.exists?(
      user_id: parent_comment.user_id,
      news_feed_id: parent_comment.news_feed_id,
      notification_type: NOTIFICATION_TYPE,
      news_comment_id: parent_comment.id,
    )
  end

  # Reserva la notificacion primero (mismo patron que los otros workers de
  # avisos -- el indice unico de DB protege ante dos jobs en simultaneo) y
  # recien despues manda el mail.
  def send_notification(parent_comment, reply)
    begin
      Notification.create!(
        user_id: parent_comment.user_id,
        news_feed_id: parent_comment.news_feed_id,
        notification_type: NOTIFICATION_TYPE,
        news_comment_id: parent_comment.id,
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      return
    end

    return unless parent_comment.user_info.present? && parent_comment.user_info['email'].present?

    locale = resolve_locale(parent_comment.user_id)

    NewsConversationReminderMailer.comment_reply_email(
      parent_comment.user_info['email'],
      locale,
      reply.news_feed,
    ).deliver_later
  end

  def resolve_locale(user_id)
    user = User.find_by(id: user_id)
    return 'es' unless user.present?

    user.language == 'por' ? 'pt' : 'es'
  end
end
