module Api
  module V1
    class NotificationsController < ApiController
      # Sin auth a proposito -- se clickea desde un link de mail, el
      # usuario nunca esta logueado en ese momento. El token firmado (ver
      # User.find_from_unsubscribe_token) es lo que identifica al usuario
      # de forma segura, no una sesion.
      def unsubscribe
        user = User.find_from_unsubscribe_token(params[:token])

        if user.present?
          user.update!(comment_notifications_opt_out: true, comment_notifications_opt_out_at: Time.current)
          render json: {success: true}, status: :ok
        else
          render json: {success: false}, status: :unprocessable_entity
        end
      end
    end
  end
end
