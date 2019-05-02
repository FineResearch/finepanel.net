# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :rememberable

  validates :encrypted_email, uniqueness: true

  attr_accessor :email, :encrypted_password

  def self.find_from_email_and_password(email, password)
    return nil unless email.present?

    encrypted_email = Digest::MD5.hexdigest(email)
    user = User.find_by(encrypted_email: encrypted_email)
    return nil unless user.present?

    user.email = email
    User.automated_password(email) == password ? user : nil
  end

  def self.automated_password(email)
    # Algorithm used to create passwords inside confirmit
    span = email[2..6]
    val = 0.0
    span.each_char do |char|
      val += char.ord
    end
    val = ((val - 240) / 370 * 10_000).floor
    val.to_s
  end
end
