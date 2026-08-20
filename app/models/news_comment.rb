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

  # -- Vaidations --
  validates :text, presence: true

  # -- Callbacks --
  after_create :deliver_notification_mails
  after_create :check_conversation_reminder
  after_create :notify_first_commenter_on_reply

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
end
