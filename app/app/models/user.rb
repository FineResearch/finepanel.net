# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :rememberable

  has_many :posts
  has_many :comments

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

  def self.find_from_email(email)
    encrypted_email = Digest::MD5.hexdigest(email)
    User.find_by(encrypted_email: encrypted_email)
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
  end

  def surveys
    ConfirmitGateway.get_surveys_for_user(self)
  end

  def payment_info
    ConfirmitGateway.get_payments_for_user(self)
  end

  def language_param(respid)
    country_id = profile_data(respid)[:country_id]
    ConfigurationReader.language_code(country_id)
  end

  def info_for_post(respid)
    user_data = profile_data(respid)
    return nil unless user_data.present?

    complete_name = user_data[:suffix] + ' ' + user_data[:last_name]
    country = ConfigurationReader.country_name(user_data[:country_id]) if user_data[:country_id].present?
    city = ConfigurationReader.city_name(user_data[:country_id], user_data[:city_id]) if user_data[:city_id].present?
    {
      complete_name: complete_name,
      specialty: user_data[:specialty_id],
      country: country,
      city: city,
      email: user_data[:email]
    }
  end

  def admin?
    admin_users = ConfigurationReader.admin_users
    admin_users.include?(email)
  end
end
