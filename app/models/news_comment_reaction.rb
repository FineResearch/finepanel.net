# frozen_string_literal: true
# == Schema Information
#
# Table name: news_comment_reactions
#
#  id             :integer          not null, primary key
#  user_id        :integer
#  news_comment_id :integer
#  user_info      :jsonb
#  reaction_type  :string           default("agree"), not null
#  created_at     :datetime
#  updated_at     :datetime

class NewsCommentReaction < ApplicationRecord
  belongs_to :user
  belongs_to :news_comment

  validates :user_id, uniqueness: { scope: :news_comment_id }
  validate :cannot_react_to_own_comment

  after_create :check_agreement_threshold

  private

  def cannot_react_to_own_comment
    return unless news_comment.present? && news_comment.user_id == user_id

    errors.add(:user_id, 'cannot react to own comment')
  end

  # Se dispara en el momento de la creacion (no en un worker diferido)
  # porque la condicion es puntual: "esta reaccion hizo que el conteo de
  # reactores distintos pase de <2 a >=2" -- un evento que ocurre una sola
  # vez en la vida del comentario, no un estado a re-evaluar mas tarde.
  # Cada create cambia el conteo en exactamente +1, asi que la primera vez
  # que llega a 2 es siempre esta transicion -- comparar "== 2" alcanza,
  # no hace falta guardar el conteo anterior. El dedup permanente (nunca
  # reenviar si baja de 2 y vuelve a subir) lo garantiza que este callback
  # solo vive en after_create (nunca en after_destroy) mas el chequeo de
  # Notification.exists? en el worker -- ver CommentAgreementNotificationWorker.
  def check_agreement_threshold
    distinct_reactors = news_comment.news_comment_reactions.distinct.count(:user_id)
    return unless distinct_reactors == 2

    CommentAgreementNotificationWorker.perform_async(news_comment_id)
  end
end
