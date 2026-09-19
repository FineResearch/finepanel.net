# frozen_string_literal: true

# Reaccion "Concordo"/"De acuerdo" a nivel de comentario (distinta de
# NewsFeedReaction, que es a nivel de noticia). A diferencia de esa, esta
# no tiene columna "useful" booleana -- la reaccion es binaria por
# presencia/ausencia de la fila (crear = reacciono, borrar = saco la
# reaccion), ver NewsCommentReaction.
#
# user_info (jsonb) es un snapshot de nombre/especialidad/pais del que
# reacciona, igual que news_comments.user_info -- no hay forma de leerlo en
# vivo del perfil sin pegarle a Confirmit (~8s por llamada, ver
# User#profile_data), asi que se replica el mismo patron: el cliente manda
# esos datos (ya los tiene en memoria de la sesion) al reaccionar.
#
# reaction_type queda pensado a futuro (hoy solo existe "agree") -- el
# indice unico NO lo incluye a proposito, porque el alcance de esta feature
# es "una reaccion por comentario", no "una por tipo".
class CreateNewsCommentReactions < ActiveRecord::Migration[5.2]
  def change
    create_table :news_comment_reactions do |t|
      t.references :user, foreign_key: true
      t.references :news_comment, foreign_key: true
      t.jsonb :user_info
      t.string :reaction_type, null: false, default: 'agree'

      t.timestamps
    end

    add_index :news_comment_reactions, [:user_id, :news_comment_id],
      unique: true, name: 'index_news_comment_reactions_on_user_and_comment'
  end
end
