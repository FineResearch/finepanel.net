class AddParentCommentIdToNewsComments < ActiveRecord::Migration[5.2]
  def change
    add_reference :news_comments, :parent_comment, foreign_key: { to_table: :news_comments, on_delete: :cascade }, null: true
  end
end
