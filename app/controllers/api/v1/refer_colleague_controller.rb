module Api
  module V1
    class ReferColleagueController < ApiController
      before_action :set_user_data

      def create
        permit_params = set_collegue_params
        user_params = ConfirmitGateway.new_colleague(permit_params)
        colleague = User.new(user_params)

        if colleague.save
          render json: :nothing, status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end
      end

      private

      def set_collegue_params
        collegue_data = collegue_params
        collegue_data[:fuente] = @current_user.email
        collegue_data[:email] = params[:source_email]
        collegue_data
      end

      def collegue_params
        params.permit(:country_id, :email, :first_name, :last_name, :specialty_id, :suffix, :source_email)
      end

    end
  end
end
