class AddActiveAppToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :active_app, :boolean
  end
end
