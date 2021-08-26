class ChangeCreditToInteger < ActiveRecord::Migration[5.2]
  def change
    change_column :payments, :credit, :integer
  end
end
