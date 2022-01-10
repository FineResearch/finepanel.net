module Api
  module V1
    class NewsMailerController < ApiController

      def create
        if validate_email_params
          NewsParser.new(params['html']).process
          render json: :nothing, status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end
      end

      private

      def validate_email_params
        allowed_emails = ENV.fetch('EMAIL_NEWS_RECIPIENT', 'test@news-test.finepanel.net').try(:split, /,\s*/)
        params['html'].present? && allowed_emails.include?(params['to'])
      end

    end
  end
end
