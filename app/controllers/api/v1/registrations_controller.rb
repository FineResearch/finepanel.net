module Api
  module V1
    class RegistrationsController < Devise::SessionsController
      skip_before_action :verify_authenticity_token
      skip_before_action :verify_signed_out_user

      def create
        user_params = ConfirmitGateway.new_account(user_data_params)
        resource = User.new(user_params)

        if resource.save
          resource.email = user_data_params[:email]
          sign_in(:user, resource)
          @current_user = resource
          render json: { email: resource.email, userInfo: {userData: UserDataBlueprint.render_as_json(user_data_params) } }, status: :ok
        else
          render json: {}, status: :unprocessable_entity
        end
      end

      private

      def user_data_params
        params.permit(:alternate_email, :alternate_specialty_id, :city, :city_id, :city_text, :country, :country_id, :country_text, :crm, :email, :first_name, :last_name, :phone, :specialty_id, :specialty_text, :suffix, :terms_conditions, :work_at_id)
      end
    end
  end
end
