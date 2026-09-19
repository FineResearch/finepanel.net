# frozen_string_literal: true

# Agrega referencia a news_comment en notifications -- necesaria para poder
# deduplicar la notificacion nueva "2 colegas concordaron con tu
# comentario" (ver Notification::TYPES[:comment_agreement]) a nivel de
# comentario puntual, no solo de noticia. Las 2 notificaciones existentes
# (news_conversation_reminder, first_comment_reply) siguen sin usar esta
# columna (queda NULL para ellas), sin cambio de comportamiento -- Postgres
# no exige unicidad entre NULLs, pero esos dos tipos ya se protegen igual
# que siempre (el chequeo de la app + este mismo indice, ahora con una
# columna mas).
class AddNewsCommentIdToNotifications < ActiveRecord::Migration[5.2]
  def change
    add_reference :notifications, :news_comment, foreign_key: { on_delete: :nullify }, null: true

    remove_index :notifications, name: 'index_notifications_on_user_news_feed_and_type'
    add_index :notifications, [:user_id, :news_feed_id, :notification_type, :news_comment_id],
      unique: true, name: 'index_notifications_on_user_news_feed_type_and_comment'
  end
end
