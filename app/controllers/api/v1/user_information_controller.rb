module Api
  module V1
    class UserInformationController < ApiController
      before_action :set_user_data

      def index
        user_info = @current_user.info_for_post(nil, params['email'])
        if user_info.present?
          render json: UserInformationBlueprint.render(user_info), status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end
      end
    end
  end
end
