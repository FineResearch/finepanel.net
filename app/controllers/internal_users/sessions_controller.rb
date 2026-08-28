# frozen_string_literal: true

module InternalUsers
  # #create default de Devise::SessionsController pasa por warden.authenticate!,
  # que en esta app llega con params[scope] como Hash plano sin acceso
  # indiferente (ver Users::SessionsController) -- se evita por completo
  # autenticando a mano. Ademas, en produccion config.session_store esta
  # deshabilitado (ver config/initializers/session_store.rb), asi que este
  # controller no usa sign_in con sesion/flash de HTML sino JSON puro: el
  # token JWT lo agrega Warden::JWTAuth::Middleware solo (dispatch_requests
  # en config/initializers/devise.rb), disparado por el sign_in exitoso.
  class SessionsController < Devise::SessionsController
    skip_before_action :verify_authenticity_token

    def create
      resource = InternalUser.find_for_database_authentication(email: params[:internal_user][:email])

      if resource&.active? && resource.valid_password?(params[:internal_user][:password])
        sign_in(resource_name, resource)
        render json: { email: resource.email, role: resource.role }, status: :ok
      else
        render json: { message: 'Email o contraseña inválidos.' }, status: :unauthorized
      end
    end

    def destroy
      render json: { message: 'Logout exitoso.' }, status: :ok
    end
  end
end
