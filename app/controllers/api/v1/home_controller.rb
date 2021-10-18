module Api
  module V1
    class HomeController < ApiController

      def stc
        stc_mx_profile_path = ConfigurationReader.stc_mx_profile_path
        stc_co_profile_path = ConfigurationReader.stc_co_profile_path
        data_mx = get_campaign_payment_data(stc_mx_profile_path)
        data_col = get_campaign_payment_data(stc_co_profile_path)

        render json: StcBlueprint.render(StcPresenter.new(data_mx, data_col).stc_object), status: :ok
      end

      private

      def get_campaign_payment_data(campaign_profile_path)
        campaign_user_data = ConfirmitGateway.get_user_attrs_from_profile(campaign_profile_path)
        {
          total_earned: ConfirmitGateway.get_payments_for_user(campaign_user_data)[:total],
          currency: ConfirmitGateway.get_currency_for_user(campaign_user_data)
        }
      end
    end
  end
end
