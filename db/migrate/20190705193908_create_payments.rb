class CreatePayments < ActiveRecord::Migration[5.2]
  def change
    create_table :payments do |t|
      t.string :respid, null: false, default: ""
      t.string :project_name
      t.float :credit, null: false, default: 0
      t.string :concept
      t.date :email_date

      t.timestamps
    end
  end
end
