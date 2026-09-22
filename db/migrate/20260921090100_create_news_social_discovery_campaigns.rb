# frozen_string_literal: true

# 1 fila por NewsFeed que dispara la campana de "descubrimiento social" --
# el indice unico en news_feed_id es la reserva atomica real (ver
# NewsSocialDiscoveryService#claim_campaign: create! + rescue
# RecordNotUnique), no un SELECT previo, para que 2 eventos concurrentes
# (ej. la reaccion util #10 y #11 llegando casi juntas) nunca disparen 2
# campanas para la misma noticia.
#
# eligible_recipient_count (tamano de la audiencia calculada en la ULTIMA
# corrida del worker) se guarda separado de recipient_count (conteo real
# de Notification creadas, recalculado siempre por COUNT contra la DB, no
# acumulado en Ruby) -- si Sidekiq reintenta el worker, recipient_count
# converge al numero correcto sin importar cuantas corridas parciales hizo
# falta.
class CreateNewsSocialDiscoveryCampaigns < ActiveRecord::Migration[5.2]
  def change
    create_table :news_social_discovery_campaigns do |t|
      t.references :news_feed, foreign_key: true, null: false
      t.datetime :triggered_at, null: false
      t.integer :useful_count_at_trigger, null: false
      t.integer :comment_count_at_trigger, null: false
      t.integer :eligible_recipient_count
      t.integer :recipient_count

      t.timestamps
    end

    add_index :news_social_discovery_campaigns, :news_feed_id, unique: true,
      name: 'index_news_social_discovery_campaigns_on_news_feed'
  end
end
