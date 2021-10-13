class AddJtiToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :jti, :string
    change_column_null :users, :jti, false
    add_index :users, :jti, unique: true
  end
end
