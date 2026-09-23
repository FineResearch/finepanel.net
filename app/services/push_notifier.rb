# frozen_string_literal: true

require 'net/http'
require 'json'
require 'jwt'
require 'openssl'

# Manda push notifications via Firebase Cloud Messaging (API HTTP v1),
# reemplazando el POST a myqmob.com/LumiSay que se usaba con la app vieja
# -- ya no dependemos de ese tercero para nada del lado del push.
#
# FCM HTTP v1 no acepta usuario/contrasena como la API vieja: exige un
# access token OAuth2 de una service account de Google, obtenido via un JWT
# firmado (flujo estandar "JWT bearer" de Google, RFC 7523) -- se
# implementa a mano con la gema jwt que ya esta en el Gemfile, en vez de
# sumar una gema nueva (google-auth) solo para esto.
#
# PASO MANUAL PENDIENTE: falta generar la service account key en Firebase
# Console (Configuracion del proyecto > Cuentas de servicio > Generar
# nueva clave privada) y cargar su JSON completo en
# ENV['FCM_SERVICE_ACCOUNT_JSON'] (secret de produccion) antes de que esto
# pueda mandar push de verdad.
class PushNotifier
  FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
  GOOGLE_TOKEN_URI = 'https://oauth2.googleapis.com/token'
  ACCESS_TOKEN_CACHE_KEY = 'fcm_access_token'
  # Google emite el access token con 1h de validez -- se cachea un poco por
  # debajo de eso para nunca usar uno vencido por un margen de reloj.
  ACCESS_TOKEN_CACHE_TTL = 55.minutes

  DEFAULT_TITLE = 'Fine Panel'
  # Un token queda invalido cuando el usuario desinstala la app o el SO lo
  # revoca -- FCM devuelve estos 2 codigos en esos casos. Cualquier otro
  # error (5xx, throttling) se deja como esta, puede ser transitorio.
  STALE_TOKEN_ERROR_STATUSES = %w[UNREGISTERED INVALID_ARGUMENT].freeze

  def initialize(user_ids, message)
    @user_ids = user_ids
    @message = message
  end

  def send_notification
    return if @user_ids.blank? || @message.blank?

    DeviceToken.where(user_id: @user_ids).find_each do |device_token|
      send_to_token(device_token.token)
    end
  end

  private

  def send_to_token(token)
    uri = URI("https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    request.body = {
      message: {
        token: token,
        notification: { title: DEFAULT_TITLE, body: @message },
      },
    }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    cleanup_if_stale(token, response) unless response.code.to_i.between?(200, 299)
  rescue StandardError => e
    Rails.logger.error("[PushNotifier] failed to send to token=#{token}: #{e.class} #{e.message}")
  end

  def cleanup_if_stale(token, response)
    status = JSON.parse(response.body).dig('error', 'status')

    DeviceToken.where(token: token).destroy_all if STALE_TOKEN_ERROR_STATUSES.include?(status)
  rescue JSON::ParserError
    nil
  end

  def project_id
    service_account['project_id']
  end

  def access_token
    Rails.cache.fetch(ACCESS_TOKEN_CACHE_KEY, expires_in: ACCESS_TOKEN_CACHE_TTL) { fetch_access_token }
  end

  def fetch_access_token
    response = Net::HTTP.post_form(
      URI(GOOGLE_TOKEN_URI),
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signed_assertion,
    )

    JSON.parse(response.body)['access_token']
  end

  def signed_assertion
    now = Time.now.to_i
    payload = {
      iss: service_account['client_email'],
      scope: FCM_SCOPE,
      aud: GOOGLE_TOKEN_URI,
      iat: now,
      exp: now + 3600,
    }

    JWT.encode(payload, private_key, 'RS256')
  end

  def private_key
    OpenSSL::PKey::RSA.new(service_account['private_key'])
  end

  def service_account
    @service_account ||= JSON.parse(ENV.fetch('FCM_SERVICE_ACCOUNT_JSON'))
  end
end
