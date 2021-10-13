class NewsCommentBlueprint < Blueprinter::Base
  identifier :id

  fields :text, :user_info

  field :date do |comment|
    comment.created_at.strftime("%d-%m-%Y")
  end
end
