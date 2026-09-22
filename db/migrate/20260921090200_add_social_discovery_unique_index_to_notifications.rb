# frozen_string_literal: true

# Guardrail real de concurrencia para el tipo news_social_discovery: no
# reusa el indice unico de 4 columnas de notifications
# (index_notifications_on_user_news_feed_type_and_comment), porque ese
# indice incluye news_comment_id, y Postgres trata cada NULL como distinto
# de cualquier otro NULL en un indice unico -- news_social_discovery
# siempre deja news_comment_id en NULL (no esta atado a un comentario
# puntual), asi que ese indice de 4 columnas NO evitaria 2 filas
# "duplicadas" para el mismo user+news_feed+tipo bajo concurrencia (mismo
# problema preexistente, no introducido aqui, que ya afecta en silencio a
# news_conversation_reminder/first_comment_reply desde
# 20260918000100_add_news_comment_id_to_notifications.rb). Este indice
# parcial de 2 columnas, sin news_comment_id de por medio, es inmune a eso.
class AddSocialDiscoveryUniqueIndexToNotifications < ActiveRecord::Migration[5.2]
  def change
    add_index :notifications, [:user_id, :news_feed_id], unique: true,
      where: "notification_type = 'news_social_discovery'",
      name: 'index_notifications_on_user_and_news_feed_for_social_discovery'
  end
end
