module Api
  module V1
    class ConfirmitCallbacksController < ApiController
      

      def update_whatsapp_status
        project_code = params[:project_code].to_s.strip
        panelist_id = params[:panelist_id].to_s.strip
        sample_number = params[:sample_number].to_s.strip
        result = params[:result].to_s.strip.downcase
        agent_intervened = cast_boolean(params[:agent_intervened])

        record = find_panelist_record(
          project_code: project_code,
          panelist_id: panelist_id,
          sample_number: sample_number
        )

        unless record.present?
          Rails.logger.warn(
            "[ConfirmitCallbacksController] Record not found " \
            "project_code=#{project_code} panelist_id=#{panelist_id} sample_number=#{sample_number}"
          )

          return render json: {
            ok: false,
            error: 'record_not_found'
          }, status: :not_found
        end

        record.mark_agent_intervened! if agent_intervened && !record.agent_intervened?
        record.mark_final_result!(result)

        Rails.logger.info(
          "[ConfirmitCallbacksController] Updated record_id=#{record.id} " \
          "project_code=#{record.project_code} panelist_id=#{record.panelist_id} " \
          "result=#{result} agent_intervened=#{record.agent_intervened}"
        )

        render json: {
          ok: true,
          id: record.id,
          project_code: record.project_code,
          panelist_id: record.panelist_id,
          status: record.status,
          confirmit_status: record.confirmit_status,
          agent_intervened: record.agent_intervened
        }, status: :ok
      rescue ArgumentError => e
        Rails.logger.warn("[ConfirmitCallbacksController] Invalid callback params: #{e.message}")

        render json: {
          ok: false,
          error: e.message
        }, status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error("[ConfirmitCallbacksController] Error: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?

        render json: {
          ok: false,
          error: 'internal_error'
        }, status: :internal_server_error
      end

      private

      def find_panelist_record(project_code:, panelist_id:, sample_number:)
        if project_code.present? && panelist_id.present?
          WhatsappProjectPanelist.find_by(
            project_code: project_code,
            panelist_id: panelist_id
          )
        elsif project_code.present? && sample_number.present?
          WhatsappProjectPanelist.find_by(
            project_code: project_code,
            sample_number: sample_number
          )
        else
          nil
        end
      end

      def cast_boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
