# frozen_string_literal: true
# == Schema Information
#
# Table name: news_comments
#
#  id                :integer          not null, primary key
#  text              :string
#  user_id           :integer
#  news_feed_id      :integer
#  user_info         :jsonb
#  created_at        :datetime
#  updated_at        :updated_at

class NewsComment < ApplicationRecord

  # -- Associations --
  belongs_to :user
  belongs_to :news_feed
  belongs_to :parent_comment, class_name: 'NewsComment', optional: true
  has_many :replies, class_name: 'NewsComment', foreign_key: :parent_comment_id, dependent: :destroy
  has_many :news_comment_reactions, dependent: :destroy

  # Anotados por el controller ANTES de renderizar (ver
  # NewsFeedController#annotate_comment_reactions), no columnas de DB --
  # evita N+1 en el blueprint (una query agregada para toda la pagina en
  # vez de una por comentario). nil si nadie los seteo (ej. al renderizar
  # un comentario recien creado en NewsCommentController#create), por eso
  # NewsCommentBlueprint los trata con "|| 0"/"|| false".
  attr_accessor :reaction_count, :my_comment_reaction

  # -- Vaidations --
  validates :text, presence: true
  validate :parent_comment_must_be_top_level

  # -- Callbacks --
  after_create :deliver_notification_mails
  after_create :check_conversation_reminder
  after_create :notify_first_commenter_on_reply
  after_create :notify_parent_comment_author

  # Solo 1 nivel de anidamiento -- no se puede responder a una respuesta.
  # Reforzado tambien en NewsCommentController#reply (mismo criterio que
  # cannot_react_to_own_comment en NewsCommentReaction: el controller evita
  # el caso comun de antemano, el modelo es la red de seguridad real).
  def parent_comment_must_be_top_level
    return unless parent_comment.present? && parent_comment.parent_comment_id.present?

    errors.add(:parent_comment_id, 'cannot reply to a reply')
  end

  def deliver_notification_mails
    NewsCommentMailer.news_comment_email(self, user.user_respid(user_info['email'])).deliver_later
  end

  def check_conversation_reminder
    NewsCommentReminderWorker.perform_async(news_feed_id)
  end

  # Se evalua en el momento de la creacion (no dentro del worker) porque la
  # condicion es "este comentario es exactamente el segundo de la noticia" -
  # un chequeo puntual en el momento del evento, no un estado que siga
  # siendo valido si se lo revisa mas tarde (a diferencia del reminder de
  # reactivacion, que si puede evaluarse de forma diferida).
  def notify_first_commenter_on_reply
    return unless news_feed.news_comments.count == 2

    FirstCommentReplyWorker.perform_async(news_feed_id)
  end

  def notify_parent_comment_author
    return unless parent_comment_id.present?

    CommentReplyNotificationWorker.perform_async(id)
  end
end
