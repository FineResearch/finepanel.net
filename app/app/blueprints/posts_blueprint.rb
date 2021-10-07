class PostsBlueprint < Blueprinter::Base
  identifier :id

  fields :text, :media, :external_media_url, :user_info, :kind

  field :date do |post|
    post.created_at.strftime("%d-%m-%Y")
  end

  association :comments, blueprint: CommentBlueprint
end
