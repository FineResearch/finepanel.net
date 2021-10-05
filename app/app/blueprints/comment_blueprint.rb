class CommentBlueprint < Blueprinter::Base
  identifier :id

  fields :text, :user_info

  field :date do |comment|
    comment.set_date
  end
end
