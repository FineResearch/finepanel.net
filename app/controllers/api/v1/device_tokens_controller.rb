# frozen_string_literal: true

module Api
  module V1
    class DeviceTokensController < ApiController
      before_action :check_basic_auth

      # Un token de FCM identifica un dispositivo concreto, no un usuario --
      # si ese mismo dispositivo se loguea despues con otra cuenta, el token
      # se reasigna en vez de duplicarse (find_or_initialize_by token, no
      # por user). Se llama despues de cada login exitoso en la app.
      def create
        device_token = DeviceToken.find_or_initialize_by(token: params[:token])
        device_token.user = current_user
        device_token.platform = params[:platform]

        if device_token.save
          render json: { success: true }, status: :ok
        else
          render json: { success: false, errors: device_token.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Se llama al desloguearse, para que ese dispositivo deje de recibir
      # avisos de la cuenta con la que ya no esta logueado.
      def destroy
        DeviceToken.where(token: params[:token], user: current_user).destroy_all

        render json: { success: true }, status: :ok
      end
    end
  end
end
