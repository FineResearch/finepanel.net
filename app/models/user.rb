# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :rememberable

  validates :encrypted_email, presence: true, uniqueness: true

  attr_accessor :email, :encrypted_password

  def self.find_from_email_and_password(email, password)
    return nil unless email.present?

    encrypted_email = Digest::MD5.hexdigest(email)
    user = User.find_by(encrypted_email: encrypted_email)
    return nil unless user.present?

    user.email = email
    User.automated_password(email) == password ? user : nil
  end

  def self.find_from_respid_spanel_and_encrypted_email(respid, spanel, encrypted_email)
    user = find_by(spanel: spanel, encrypted_email: encrypted_email)
    return nil unless user.present?
    data = user.profile_data(respid)
    user.email = data[:email]

    user.hash_respid == (respid + automated_password(user.email)) ? user : nil
    user
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

  def user_profile_url(respid)
    ConfigurationReader.user_profile_path + '&r=' + respid.to_s + '&s=' + spanel
  end

  def user_respid(email)
    hash_respid.to_i - self.class.automated_password(email).to_i
  end

  def profile_data_from_email(email)
    respid = hash_respid.to_i - self.class.automated_password(email).to_i
    profile_data(respid)
  end

  def profile_data(respid)
    @profile_data ||= ConfirmitGateway
      .get_user_attrs_from_profile(user_profile_url(respid))
      .with_indifferent_access
  end

  def surveys
    ConfirmitGateway.get_surveys_for_user(self)
  end

  def payment_info
    ConfirmitGateway.get_payments_for_user(self)
  end
end
