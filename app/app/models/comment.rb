# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post

  after_create :deliver_notification_mails

  def deliver_notification_mails
    CommentMailer.new_comment_email(self, user.user_respid(user_info['email'])).deliver
    recipients = post.participants_emails
    recipients.delete(user_info['email'])
    if recipients.count > 0
      recipients = recipients.join(',')
      CommentMailer.new_comment_email_for_participants(self, recipients).deliver
    end
  end
end
