module Api
  module V1
    class SurveysController < ApiController
      before_action :set_user_data

      def index
        survey_list = ConfirmitGateway.get_surveys_for_user(@resource, @resource.user_respid(@resource.email))

        if survey_list.present?
          render json: SurveyBlueprint.render(survey_list), status: :ok
        else
          render json: [], status: :ok
        end
      end

      def participations
        last_participation = ConfirmitGateway.get_participations_for_user(@user_data, {locale: params.dig("locale")}).first
        formatted_text = resolve_participations_text(last_participation, params.dig("locale"))

        render json: LastParticipationBlueprint.render(LastParticipationPresenter.new(formatted_text).last_participation), status: :ok
      end

      private

      def resolve_participations_text(survey, locale)
        return 'false' unless survey.present?
        "#{survey[:project]} #{I18n.with_locale(locale){I18n.t('dashboard.survey_history.the')}} #{survey[:date]}"
      end

    end
  end
end
