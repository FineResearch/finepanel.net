class AddUniqueIndexes < ActiveRecord::Migration[5.2]
  def change
    add_index :payments, [:respid, :project_name, :credit, :concept, :email_date], unique: true, name: :unique_payments
  end
end
