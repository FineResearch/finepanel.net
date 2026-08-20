# frozen_string_literal: true

class Internal::FinePanelSetup::SetupController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    render file: Rails.root.join('public', 'fine-panel-setup', 'index.html'), layout: false
  end

  def duplicate
    source_project_id = params[:source_project_id].to_s.strip
    new_project_name = params[:new_project_name].to_s.strip

    if source_project_id.blank? || new_project_name.blank?
      return render json: { ok: false, error: 'source_project_id y new_project_name son obligatorios' }, status: :unprocessable_entity
    end

    result = ::FinePanelSetup::ConfirmitSoapClient.new.duplicate_project(
      source_project_id: source_project_id,
      new_project_name: new_project_name
    )

    if result[:ok]
      render json: { ok: true, project_id: result[:project_id] }
    else
      render json: { ok: false, error: result[:error] }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#duplicate] #{e.class} - #{e.message}")
    render json: { ok: false, error: 'internal_error' }, status: :internal_server_error
  end
end
