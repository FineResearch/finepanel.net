module Api
  module V1
    class UserInformationController < ApiController
      before_action :set_user_data

      def index
        user_data = @current_user.profile_data(@current_user.user_respid(@current_user.email))

        if user_data.present?
          render json: UserProfileBlueprint.render(user_data), status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end
      end

      def update_profile
        if ConfirmitGateway.update_user(@current_user.user_respid(@current_user.email), @current_user.spanel, user_profile_params)
          render json: :nothing, status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end
      end

      def update_payment_data
        if ConfirmitGateway.update_user_payment_data(@current_user.user_respid(@current_user.email), @current_user.spanel, payment_data_params)
          render json: :nothing, status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end
      end

      private

      def user_profile_params
        params.permit(:alternate_email, :alternate_specialty_id, :city, :city_id, :city_text, :country, :country_id, :country_text, :crm, :email, :first_name, :last_name, :phone, :specialty_id, :specialty_text, :suffix, :terms_conditions, :work_at_id)
      end

      def payment_data_params
         params.permit(:bank_name, :bank_branch, :bank_account_type, :bank_account_owner, :bank_account_name, :bank_account_number)
      end
    end
  end
end
