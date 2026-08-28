class InternalUser < ApplicationRecord
  # No :registerable a proposito -- son cuentas corporativas fijas, creadas a
  # mano (ver db/seeds.rb), no autoregistro publico. No :confirmable -- no
  # hay flujo de confirmacion de email para estas cuentas.
  devise :database_authenticatable, :recoverable, :rememberable

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

  # El resto de la app no usa el mailer estandar de ActionMailer para enviar
  # de verdad -- todo pasa por la API de SendGrid (ver ApplicationMailer).
  # Devise::Recoverable llama a esto internamente para el email de
  # "olvide mi contrasena"; se intercepta solo esa notificacion puntual y se
  # manda por el mismo mecanismo que ya usa el resto de la app (texto plano,
  # sin necesitar un template dinamico nuevo en SendGrid) en vez de dejar que
  # Devise intente entregarlo por el ActionMailer default, que no esta
  # configurado para enviar nada real en este proyecto.
  def send_devise_notification(notification, *args)
    return super unless notification == :reset_password_instructions

    token = args.first
    reset_url = Rails.application.routes.url_helpers.edit_internal_user_password_url(
      reset_password_token: token,
      host: ENV.fetch('APP_HOST', 'localhost:3000')
    )

    ApplicationMailer.send_plain_email(
      to: email,
      from: 'admin@finepanel.net',
      subject: 'Recuperar contraseña - Fine Panel Setup',
      text_body: "Para elegir una contraseña nueva, entrá a este link:\n\n#{reset_url}\n\nSi no lo pediste vos, podés ignorar este mensaje."
    )
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
