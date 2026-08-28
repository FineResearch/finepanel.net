# frozen_string_literal: true

class Internal::FinePanelSetup::SetupController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_internal_user!

  def index
    render file: Rails.root.join('public', 'fine-panel-setup', 'index.html'), layout: false
  end

  def duplicate
    source_project_id = params[:source_project_id].to_s.strip
    new_project_name = params[:new_project_name].to_s.strip
    generated_script = params[:generated_script].to_s

    if source_project_id.blank? || new_project_name.blank?
      return render json: { ok: false, error: 'source_project_id y new_project_name son obligatorios' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    result = client.duplicate_project(
      source_project_id: source_project_id,
      new_project_name: new_project_name
    )

    unless result[:ok]
      return render json: { ok: false, error: result[:error] }, status: :unprocessable_entity
    end

    # TODO: una vez confirmado con Forsta soporte el formato de Update/SurveySchema,
    # escribir generated_script en el nodo "definiciones" del proyecto recien
    # duplicado (result[:project_id]) usando ::FinePanelSetup::ConfirmitSoapClient
    # #build_definitions_script (ya armado, preserva la parte de FASE B en adelante)
    # + el Update pendiente. Por ahora no se toca nada mas en Confirmit.
    render json: { ok: true, project_id: result[:project_id] }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#duplicate] #{e.class} - #{e.message}")
    render json: { ok: false, error: 'internal_error' }, status: :internal_server_error
  end

  # Paso 2 del wizard: "lanza" el proyecto (crea la base de datos, pone el
  # proyecto en Production) via LaunchSurvey y espera a que el TaskID
  # asincronico termine antes de responder -- sin esto el proyecto duplicado
  # no tiene base de datos y ni el link generico ni la clave funcionan.
  # timeout mas alto que el default de wait_for_task (60s) porque
  # CreateNewDatabase puede tardar mas que eso contra un proyecto real.
  def launch
    project_id = params[:project_id].to_s.strip

    if project_id.blank?
      return render json: { ok: false, error: 'project_id es obligatorio' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    task_id = client.launch_survey(project_id: project_id)
    status = client.wait_for_task(task_id: task_id, timeout_seconds: 180, poll_interval: 5)

    if status == 'Complete'
      render json: { ok: true, task_id: task_id, status: status }
    else
      render json: { ok: false, error: "LaunchSurvey termino con estado \"#{status}\" (TaskID #{task_id})", task_id: task_id, status: status }
    end
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#launch] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Paso 3 del wizard: lee la clave del proyecto desde el link generico
  # publico (solo funciona si el proyecto ya fue lanzado -- ver #launch). No
  # escribe nada en Confirmit todavia -- eso es el paso siguiente (pisar el
  # placeholder en el nodo "definiciones" con esta clave real).
  def fetch_key
    project_id = params[:project_id].to_s.strip

    if project_id.blank?
      return render json: { ok: false, error: 'project_id es obligatorio' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    key = client.fetch_project_key(project_id: project_id)

    render json: { ok: true, key: key }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#fetch_key] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Paso 4 del wizard: arma el ScriptCode final del nodo "definiciones"
  # (reemplaza la parte A1-A10 por generated_script, preserva la parte de
  # FASE B en adelante, y pisa el placeholder de la clave con la real -- ver
  # ConfirmitSoapClient#build_definitions_script) y lo escribe de verdad via
  # Update. project_key es opcional: sin ella escribe el script pero deja el
  # placeholder de clave que ya trae el proyecto duplicado.
  def write_definitions
    project_id = params[:project_id].to_s.strip
    generated_script = params[:generated_script].to_s
    project_key = params[:project_key].to_s.strip.presence
    primerid_lines = params[:primerid_lines].to_s.presence

    if project_id.blank? || generated_script.blank?
      return render json: { ok: false, error: 'project_id y generated_script son obligatorios' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    script_code = client.build_definitions_script(
      project_id: project_id,
      generated_script: generated_script,
      project_key: project_key,
      primerid_lines: primerid_lines
    )
    client.write_definitions_script(project_id: project_id, script_code: script_code)

    render json: { ok: true }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#write_definitions] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Paso opcional, solo cuando la programacion del estudio NO es de Fine en
  # Confirmit: agrega el mapeo Fine<->Forsta (codigo FP-XXXX -> pXXXX...) al
  # proyecto de redirect compartido (p1773348171 por default -- ver
  # ConfirmitSoapClient::FNP_ASSIGNMENT_PROJECT_ID) y lo relanza para publicar
  # el cambio. generate_db_option usa el default de launch_survey ("Rebuild")
  # a proposito -- ver el comentario ahi.
  #
  # key compartida entre el Update y el Launch a proposito -- NO sacar esto.
  # Confirmado con logs reales de Confirmit (2026-08-25): si el Update
  # (append_fnp_assignment) y el Launch usan sesiones (LogOnUser) distintas,
  # el Launch a veces salta la regeneracion de base de datos y el routing
  # nuevo no queda publicado, aunque ambas llamadas devuelvan éxito. Con la
  # MISMA sesion para las dos, el problema no aparece (probado repetidas
  # veces). Un intento previo de arreglar esto con un sleep entre medio NO
  # funciono -- no es un tema de timing, es la sesion.
  def add_fnp_redirect
    fine_project_code = params[:fine_project_code].to_s.strip
    forsta_project_id = params[:forsta_project_id].to_s.strip
    redirect_project_id = params[:redirect_project_id].to_s.strip.presence || ::FinePanelSetup::ConfirmitSoapClient::FNP_ASSIGNMENT_PROJECT_ID

    if fine_project_code.blank? || forsta_project_id.blank?
      return render json: { ok: false, error: 'fine_project_code y forsta_project_id son obligatorios' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    shared_key = client.log_on

    client.append_fnp_assignment(
      fine_project_code: fine_project_code,
      forsta_project_id: forsta_project_id,
      project_id: redirect_project_id,
      key: shared_key
    )

    task_id = client.launch_survey(project_id: redirect_project_id, key: shared_key)
    status = client.wait_for_task(task_id: task_id, timeout_seconds: 180, poll_interval: 5)

    if status == 'Complete'
      render json: { ok: true, task_id: task_id, status: status }
    else
      render json: { ok: false, error: "Relanzamiento del redirect termino con estado \"#{status}\" (TaskID #{task_id})", task_id: task_id, status: status }
    end
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#add_fnp_redirect] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  def apply_emails
    project_id = params[:project_id].to_s.strip
    cartas = params.permit(
      cartas: %i[tipo group_code lang is_first_of_language existing_name name subject body_html]
    )[:cartas].to_a.map { |carta| carta.to_h.symbolize_keys }

    if project_id.blank? || cartas.empty?
      return render json: { ok: false, error: 'project_id y cartas son obligatorios' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    applied = client.apply_email_cartas(project_id: project_id, cartas: cartas)

    render json: { ok: true, applied: applied }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#apply_emails] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Sube (reemplazando el bloque de ese pais, ver ConfirmitSoapClient#upload_country_links)
  # el .txt de links de cliente para un pais -- solo aplica cuando la
  # programacion es externa. primer_id viene del bloque calculado en el
  # generador (A11), no se recalcula del lado del servidor.
  def upload_client_links
    project_id = params[:project_id].to_s.strip
    primer_id = params[:primer_id].to_i
    rows = params.permit(rows: %i[id link])[:rows].to_a.map { |row| row.to_h.symbolize_keys }

    if project_id.blank? || primer_id <= 0 || rows.empty?
      return render json: { ok: false, error: 'project_id, primer_id y rows son obligatorios' }, status: :unprocessable_entity
    end
    if rows.length > 500
      return render json: { ok: false, error: "Maximo 500 links por pais (llegaron #{rows.length})" }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    result = client.upload_country_links(project_id: project_id, primer_id: primer_id, rows: rows)

    render json: { ok: true, added: result[:added], removed: result[:removed] }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#upload_client_links] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end
end
