class CreateComments < ActiveRecord::Migration[5.2]
  def change
    create_table :comments do |t|
      t.string :text
      t.references :user
      t.references :post
      t.jsonb :user_info

      t.timestamps
    end
  end
end
