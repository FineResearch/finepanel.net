module Api
  module V1
    class ApiController < ActionController::Base
      before_action :check_basic_auth, :set_user_data
      skip_before_action :verify_authenticity_token
      private
      def check_basic_auth
        # unless request.authorization.present?
        #   head :unauthorized
        #   return
        # end
        authenticate_with_http_basic do |email, password|
          user = User.first
          if true
            @current_user = user
          else
            head :unauthorized
          end
        end
      end

      def current_user
        @current_user
      end

      def set_user_data
        @resource = User.find_from_email_and_password('xxx@fine-research.com', 'xxx') rescue nil
        return unless @resource.present?
        @user_data = @resource.profile_data(@resource.user_respid(@resource.email))
      end
    end
  end
end
