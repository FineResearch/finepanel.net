# frozen_string_literal: true

# Registra lectores identificables de Fine Medical Updates: 1 fila por
# (usuario, noticia), la primera vista gana. Resuelve 2 huecos que no
# tenia el sistema -- "base de lectores" y "especialidad del lector" --
# sin agregar ninguna llamada nueva a Confirmit: specialty_id se resuelve
# server-side contra el slug que ya manda el frontend (mismo mecanismo que
# ya usa la creacion de NewsFeed), y respid se calcula con
# user.user_respid(email) (aritmetica pura, sin HTTP). Usado por
# NewsSocialDiscoveryWorker para armar la audiencia de la campana de
# "descubrimiento social".
class CreateNewsFeedViews < ActiveRecord::Migration[5.2]
  def change
    create_table :news_feed_views do |t|
      t.references :user, foreign_key: true, null: false
      t.references :news_feed, foreign_key: true, null: false
      t.references :specialty, foreign_key: true, null: true
      t.string :respid
      t.string :email

      t.timestamps
    end

    add_index :news_feed_views, [:news_feed_id, :user_id], unique: true,
      name: 'index_news_feed_views_on_news_feed_and_user'

    # Soporta la query de audiencia: WHERE specialty_id = ? + DISTINCT ON
    # (user_id) ORDER BY user_id, created_at DESC.
    add_index :news_feed_views, [:specialty_id, :user_id, :created_at],
      name: 'index_news_feed_views_on_specialty_user_and_created_at'
  end
end
