module Api
  module V1
    class PaymentsController < ApiController
      before_action :set_user_data

      def index
        payments = ConfirmitGateway.get_payments_for_user(@user_data)
        currency = ConfirmitGateway.get_currency_for_user(@user_data) || ''
        history = Payment.get_payment_history_for_user(@resource.user_respid(@resource.email)).first

        render json: PaymentSummaryBlueprint.render(PaymentSummaryPresenter.new(payments, currency, history).payment_summary), status: :ok
      end

    end
  end
end
