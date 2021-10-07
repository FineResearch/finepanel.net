# frozen_string_literal: true

class Post < ApplicationRecord
  belongs_to :user
  has_many :comments, dependent: :destroy

  validates :text, presence: true
  validate :valid_external_media_url, if: lambda { external_media_url.present? && kind == Post::TYPE[:with_image]}

  mount_uploader :media, MediaUploader

  after_destroy :delete_media_folder
  after_create :deliver_notification_mails

  scope :by_created_at, -> { order(created_at: :desc) }

  # will paginate per page default value for posts
  self.per_page = 5
  ENTRIES_LIMIT = 4 * self.per_page
  TYPE = { all: "all", with_image: "image", text: "text", with_video: "video", comment: "comment", with_document: "document" }

  def valid_external_media_url
    return if external_media_url.match(/(http(s?):)([\/|.|\w|\s|-])*\.(?:jpg|gif|png|jpeg|bmp)/)
    errors.add(:external_media_url, "invalid url")
  end

  def delete_media_folder
    FileUtils.rm_rf(Rails.root.join('public/uploads/post/media', id.to_s))
  end

  def participants_emails
    emails = comments.map{ |comment| comment.user_info['email'] }.uniq
    emails << user_info['email']
  end

  def deliver_notification_mails
    PostMailer.new_post_email(self, user.user_respid(user_info['email'])).deliver_later
  end
end
