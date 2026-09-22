# frozen_string_literal: true

# Soporta la query del cooldown de 30 dias cruzando articulos en
# NewsSocialDiscoveryWorker: Notification.where(notification_type:
# ...).where('created_at >= ?', 30.days.ago). Ningun indice existente en
# notifications sirve una WHERE encabezada por notification_type +
# created_at.
class AddTypeAndCreatedAtIndexToNotifications < ActiveRecord::Migration[5.2]
  def change
    add_index :notifications, [:notification_type, :created_at],
      name: 'index_notifications_on_type_and_created_at'
  end
end
