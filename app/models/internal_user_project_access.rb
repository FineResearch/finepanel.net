class InternalUserProjectAccess < ApplicationRecord
  belongs_to :internal_user

  validates :project_code, presence: true
  validates :internal_user_id, uniqueness: {
    scope: :project_code,
    message: 'already has access to this project'
  }

  validate :only_operator_needs_project_scoping
  before_validation :normalize_project_code

  scope :for_project, ->(project_code) { where(project_code: project_code.to_s) }

  private

  def normalize_project_code
    self.project_code = project_code.to_s.strip
  end

  def only_operator_needs_project_scoping
    return if internal_user.blank?
    return if internal_user.operator?

    errors.add(:internal_user, 'project access should only be assigned to operators')
  end
end
