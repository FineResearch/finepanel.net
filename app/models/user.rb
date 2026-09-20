# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable, :registerable, :rememberable, :jwt_authenticatable, jwt_revocation_strategy: self

  has_many :posts
  has_many :comments
  has_many :news_comments
  has_many :notifications
  has_many :news_feed_reactions
  has_many :news_comment_reactions

  scope :with_active_app, -> { where(active_app: true) }

  validates :encrypted_email, presence: true, uniqueness: true

  attr_accessor :email, :encrypted_password

  enum language: [:es, :por]

  def jwt_payload
    self.jti = self.class.generate_jti
    self.save

    super.merge('jti' => self.jti)
  end

  def self.find_from_jti_and_email(token, email)
    return nil unless email.present?

    encrypted_email = Digest::MD5.hexdigest(email)

    user = User.find_by(encrypted_email: encrypted_email, jti: token)

    return nil unless user.present?

    user.email = email
    user
  end

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

  # Token firmado (no adivinable, a diferencia de encrypted_email) para el
  # link de "no quiero mas avisos de comentarios" -- sin expiracion a
  # proposito, un link de un mail de hace meses tiene que seguir andando.
  # El "purpose" evita que este mismo token sirva para otra cosa si en el
  # futuro se firma algo mas con message_verifier.
  def self.find_from_unsubscribe_token(token)
    user_id = Rails.application.message_verifier(:comment_notifications_unsubscribe).verify(token)
    find_by(id: user_id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def comment_notifications_unsubscribe_token
    Rails.application.message_verifier(:comment_notifications_unsubscribe).generate(id)
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

  # @profile_data solo memoiza dentro de la misma instancia/request -- cada
  # request de Rails carga un User nuevo, asi que no evita nada entre
  # requests. En la practica login, user_information, surveys, payments y
  # varios endpoints mas (todos via profile_data/profile_data_from_email)
  # piden la MISMA respuesta de Confirmit para el mismo respid+spanel unos
  # segundos aparte -- confirmado 2026-08-31 con timings reales (~8s cada
  # una). El cache es corto a proposito: alcanza para cubrir ese ida y
  # vuelta entre requests sin arriesgar servir datos de pago/perfil
  # desactualizados por mucho tiempo.
  PROFILE_DATA_CACHE_TTL = 5.minutes

  def profile_data(respid)
    @profile_data ||= Rails.cache.fetch("confirmit_profile_data/#{respid}/#{spanel}", expires_in: PROFILE_DATA_CACHE_TTL) do
      ConfirmitGateway.get_user_attrs_from_profile(user_profile_url(respid))
    end
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

  def info_for_post(respid, email = nil)
    user_data = email.present? ? profile_data(user_respid(email)) : profile_data(respid)
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

  def self.bank_account_type_param(type)
    case type
      when 'saving_account'
        '1'
      when 'checking_account'
        '2'
      when 'other'
        '3'
      else
        ''
    end
  end
end
