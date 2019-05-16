class AddIndexSpanelToUser < ActiveRecord::Migration[5.2]
  def change
    add_index :users, :spanel
  end
end
