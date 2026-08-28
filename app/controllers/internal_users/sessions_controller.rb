# frozen_string_literal: true

module InternalUsers
  # El #create default de Devise::SessionsController pasa por
  # warden.authenticate!, que en esta app llega con params[scope] como Hash
  # plano (sin acceso indiferente) -- busca params[scope][:email] (symbol) y
  # nunca lo encuentra, aunque el Hash tenga la clave string "email" con el
  # valor correcto (confirmado 2026-08-28 instrumentando la estrategia
  # directamente). Mismo problema que ya evita Users::SessionsController,
  # que tampoco usa warden.authenticate! -- se sigue el mismo patron: buscar
  # el usuario y autenticar a mano con params de nivel controller (que si
  # tienen acceso indiferente), y despues sign_in directo.
  class SessionsController < Devise::SessionsController
    def create
      resource = InternalUser.find_for_database_authentication(email: params[:internal_user][:email])

      if resource&.active? && resource.valid_password?(params[:internal_user][:password])
        sign_in(resource_name, resource)
        respond_with resource, location: after_sign_in_path_for(resource)
      else
        flash[:alert] = 'Email o contraseña inválidos.'
        redirect_to new_internal_user_session_path
      end
    end
  end
end
