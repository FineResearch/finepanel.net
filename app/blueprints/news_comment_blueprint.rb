class NewsCommentBlueprint < Blueprinter::Base
  identifier :id

  fields :text, :user_info

  field :date do |comment|
    comment.created_at.strftime("%d-%m-%Y")
  end

  # reaction_count/my_comment_reaction los setea el controller ANTES de
  # renderizar (ver NewsFeedController#annotate_comment_reactions), no son
  # columnas de DB -- pueden venir nil si el comentario se renderiza sin
  # pasar por ahi (ej. NewsCommentController#create, un comentario recien
  # creado nunca tiene reacciones todavia), de ahi el "|| 0"/"|| false".
  field :reactionCount do |comment|
    comment.reaction_count || 0
  end

  field :myReaction do |comment|
    comment.my_comment_reaction || false
  end

  field :parentCommentId do |comment|
    comment.parent_comment_id
  end
end
