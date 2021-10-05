module Api
  module V1
    class UserInformationController < ApiController
      before_action :set_user_data

      def index
        if @user_data.present?
          render json: UserInformationBlueprint.render(@user_data), status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end
      end
    end
  end
end
