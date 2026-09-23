# frozen_string_literal: true

class DeviceToken < ApplicationRecord
  PLATFORMS = %w[ios android].freeze

  # -- Associations --
  belongs_to :user

  # -- Validations --
  validates :token, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
end
