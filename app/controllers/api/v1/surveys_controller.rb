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
        last_participations = ConfirmitGateway.get_participations_for_user(@user_data, {locale: params.dig("locale")})
        formatted_text = resolve_participations_text(last_participations.try(:first), params.dig("locale"))

        render json: ParticipationsBlueprint.render(LastParticipationPresenter.new(formatted_text, last_participations, params.dig("locale")).last_participations), status: :ok
      end

      private

      def resolve_participations_text(survey, locale)
        return 'false' unless survey.present?
        date = I18n.with_locale(locale) { I18n.l(survey[:date], format: :participation_date) }
        "#{survey[:project]} #{I18n.with_locale(locale){I18n.t('dashboard.survey_history.the')}} #{date}"
      end

    end
  end
end
