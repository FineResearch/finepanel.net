module Api
  module V1
    class SessionsController < Devise::SessionsController
      skip_before_action :verify_authenticity_token
      skip_before_action :verify_signed_out_user

      def create
        user = User.find_from_email_and_password(params[:email], params[:password])

        if user.present?
          sign_in(resource_name, user)
          @current_user = user
          survey_list = ConfirmitGateway.get_surveys_for_user(@current_user, @current_user.user_respid(@current_user.email))
          render json: { email: user.email, userInfo: {surveys: survey_list}}, status: :ok
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
