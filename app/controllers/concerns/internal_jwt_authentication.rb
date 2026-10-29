# frozen_string_literal: true

# Autenticacion compartida de las herramientas internas (Wizard, inbox de
# WhatsApp, Automated Transcripts): todas aceptan el mismo "Authorization:
# Bearer <jwt>" que emite POST /internal/auth/login (ver InternalUser).
#
# El token se decodifica con el decodificador de devise-jwt, que valida firma
# y vencimiento -- un token armado a mano con un jti conocido, o vencido, no
# sirve. Despues se busca el InternalUser activo por jti.
module InternalJwtAuthentication
  extend ActiveSupport::Concern

  private

  # InternalUser activo dueno del Bearer token, o nil si no hay token valido.
  def internal_user_from_bearer
    return @internal_user_from_bearer if defined?(@internal_user_from_bearer)

    @internal_user_from_bearer = find_internal_user_from_bearer
  end

  def find_internal_user_from_bearer
    token = request.authorization.to_s.split('Bearer ').last
    return nil if token.blank?

    jti = decode_internal_jwt(token)&.fetch('jti', nil)
    return nil if jti.blank?

    InternalUser.active.find_by(jti: jti)
  end

  def decode_internal_jwt(token)
    Warden::JWTAuth::TokenDecoder.new.call(token)
  rescue StandardError
    nil
  end
end
