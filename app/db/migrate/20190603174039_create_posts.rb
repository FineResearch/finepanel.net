class CreatePosts < ActiveRecord::Migration[5.2]
  def change
    create_table :posts do |t|
      t.string :text
      t.references :user
      t.string :media
      t.string :external_media_url
      t.string :kind
      t.jsonb :user_info
      
      t.timestamps
    end
  end
end
