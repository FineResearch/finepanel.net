# frozen_string_literal: true
# == Schema Information
#
# Table name: notifications
#
#  id                :integer          not null, primary key
#  user_id           :integer
#  news_feed_id      :integer
#  notification_type :string
#  news_comment_id   :integer
#  created_at        :datetime
#  updated_at        :updated_at

class Notification < ApplicationRecord
  # -- Associations --
  belongs_to :user
  belongs_to :news_feed
  belongs_to :news_comment, optional: true

  # -- Vaidations --
  validates :notification_type, presence: true
  validates :user_id, uniqueness: { scope: [:news_feed_id, :notification_type, :news_comment_id] }

  TYPES = {
    news_conversation_reminder: 'news_conversation_reminder',
    first_comment_reply: 'first_comment_reply',
    comment_agreement: 'comment_agreement',
    comment_reply: 'comment_reply'
  }.freeze
end
