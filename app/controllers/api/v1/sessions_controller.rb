module Api
  module V1
    class SessionsController < Devise::SessionsController
      skip_before_action :verify_authenticity_token
      skip_before_action :verify_signed_out_user

      def create
        if params[:email].present?
          user = User.find_from_email_and_password(params[:email], params[:password])
        else
          user = User.find_from_respid_spanel_and_encrypted_email(params[:r], params[:s], params[:e])
        end

        if user.present?
          sign_in(resource_name, user)
          @current_user = user
          render json: { email: user.email, userInfo: {surveys: []}}, status: :ok
        else
          render json: {message: 'User not found'}, status: :not_found
        end
      end

      def destroy
        unless request.authorization.present?
          render json: {message: 'Unauthorized'}, status: :unauthorized
        else
          render json: {message: 'Logout Success'}, status: :ok
        end
      end

    end
  end
end
