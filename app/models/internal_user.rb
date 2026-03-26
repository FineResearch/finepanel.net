class InternalUser < ApplicationRecord
  ROLES = %w[superadmin admin operator].freeze

  has_many :internal_user_project_accesses, dependent: :destroy

  has_many :sent_whatsapp_messages,
           class_name: 'WhatsappMessage',
           foreign_key: :internal_user_id,
           inverse_of: :internal_user

  has_many :resolved_whatsapp_conversations,
           class_name: 'WhatsappConversation',
           foreign_key: :resolved_by_user_id,
           inverse_of: :resolved_by_user

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :active, inclusion: { in: [true, false] }

  before_validation :normalize_email

  scope :active, -> { where(active: true) }
  scope :operators, -> { where(role: 'operator') }
  scope :admins, -> { where(role: ['superadmin', 'admin']) }

  def superadmin?
    role == 'superadmin'
  end

  def admin?
    role == 'admin'
  end

  def operator?
    role == 'operator'
  end

  def admin_like?
    superadmin? || admin?
  end

  def accessible_project_codes
    return [] unless active?
    return nil if admin_like?

    internal_user_project_accesses.pluck(:project_code)
  end

  def can_access_project?(project_code)
    return false unless active?
    return true if admin_like?

    internal_user_project_accesses.where(project_code: project_code.to_s).exists?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
