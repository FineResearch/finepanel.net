class AddCommentNotificationsOptOutToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :comment_notifications_opt_out, :boolean, default: false, null: false
    add_column :users, :comment_notifications_opt_out_at, :datetime
  end
end
