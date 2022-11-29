class AddColumnsToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :country, :string
    add_column :users, :whatsapp_number, :string
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :professional_title, :string
    add_column :users, :formal_title, :string
  end
end
