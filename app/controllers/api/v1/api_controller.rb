module Api
  module V1
    class ApiController < ActionController::Base
      skip_before_action :verify_authenticity_token

      protected

      def check_basic_auth
        unless request.authorization.present?
          render json: {message: 'Unauthorized'}, status: :unauthorized
          return
        end

        user = User.find_by_jti(resolve_jwt_token(request.authorization))

        if user.present?
          @current_user = user
        else
          render json: {message: 'Unauthorized'}, status: :unauthorized
        end
      end

      def set_user_data
        unless request.authorization.present? && params['email'].present?
          render json: {message: 'Unauthorized'}, status: :unauthorized
          return
        end

        @resource = User.find_from_jti_and_email(resolve_jwt_token(request.authorization), params['email'])
        if @resource.present?
          @current_user = @resource
          @user_data = @resource.profile_data(@resource.user_respid(@resource.email))
        else
          render json: {message: 'Unauthorized'}, status: :unauthorized
          return
        end
      end

      def resolve_jwt_token(authorization)
        token = authorization.split('Bearer ').last
        decode_token = JWT.decode(token, nil, false)

        jti = decode_token[0]['jti']
      end

      def user_params_info
        return {} unless params[:text].present?
        {email: params[:email], complete_name: params[:complete_name] , country: params[:country], city: params[:city], specialty: params[:specialty]}
      end
    end
  end
end
