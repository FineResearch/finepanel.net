# frozen_string_literal: true

class Internal::FinePanelSetup::SetupController < ApplicationController
  include InternalJwtAuthentication

  skip_before_action :verify_authenticity_token
  # index sirve el shell estatico sin auth (login/token se resuelven del
  # lado del cliente, ver public/fine-panel-setup/index.html) -- en
  # produccion config.session_store esta deshabilitado (auth real es JWT,
  # ver config/initializers/session_store.rb), asi que no hay sesion server
  # side con la que gatear esta accion. Todo lo que efectivamente hace algo
  # (duplicate, launch, etc.) exige Bearer token via #authenticate_via_jwt!.
  before_action :authenticate_via_jwt!, except: [:index]

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
    # Solo para agregar UN pais a un proyecto YA lanzado (ver
    # #client_links_status/read_current_primerid_lines): en vez de pisar el
    # bloque C4 entero con lo que recalcula el formulario (primerid_lines,
    # que puede correr el bloque de un pais que ya esta en produccion si el
    # orden de paises tildados cambio), se lee el C4 actual del proyecto en
    # vivo y se le agrega SOLO esta linea nueva al final -- las lineas de
    # los demas paises quedan intactas, tal cual estan hoy. Pedido del
    # usuario 2026-09-14.
    append_primerid_line = params[:append_primerid_line].to_s.strip.presence

    if project_id.blank? || generated_script.blank?
      return render json: { ok: false, error: 'project_id y generated_script son obligatorios' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new

    if append_primerid_line.present?
      primerid_lines = client.merged_primerid_lines(project_id: project_id, new_line: append_primerid_line)
    end

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

  # Lee el estado actual de listadeids de un proyecto -- usado antes de
  # agregar un pais a un proyecto YA lanzado, para saber donde arranca el
  # proximo bloque de 500 libre (en vez de confiar en el calculo por
  # formula del frontend, que asume que el orden de paises tildados hoy
  # coincide con el usado en el lanzamiento original) y para poder chequear
  # colisiones antes de subir. Pedido del usuario 2026-09-14.
  def client_links_status
    project_id = params[:project_id].to_s.strip
    return render json: { ok: false, error: 'project_id es obligatorio' }, status: :unprocessable_entity if project_id.blank?

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    existing_ids = client.read_client_link_ids(project_id: project_id)
    max_precode = existing_ids.map { |a| a[:precode].to_i }.max || 0
    block_size = ::FinePanelSetup::ConfirmitSoapClient::CLIENT_LINKS_BLOCK_SIZE
    next_primer_id = (max_precode / block_size) * block_size + 1

    render json: {
      ok: true,
      existing_ids: existing_ids,
      next_primer_id: next_primer_id,
    }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#client_links_status] #{e.class} - #{e.message}")
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

  # Paso previo a subir los links de cliente: vacia por completo listadeids/
  # listadelinks antes de empezar a subir paises. El "modelo" que se duplica
  # puede ser un proyecto reusado de una campaña anterior con datos viejos
  # que no matchean el rango de precode de esta campaña (mismo problema que
  # ya vimos con los nodos Email) -- sin este paso, un ID real repetido entre
  # campañas puede quedar con dos entradas en listadelinks (la vieja y la
  # nueva) y Confirmit resuelve el lookup de forma ambigua. Se llama UNA sola
  # vez antes del loop por pais, nunca por pais individual (si se llamara por
  # pais, cada pais nuevo borraria los que ya se subieron antes en la misma
  # corrida).
  def clear_client_links
    project_id = params[:project_id].to_s.strip

    if project_id.blank?
      return render json: { ok: false, error: 'project_id es obligatorio' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    client.clear_client_links(project_id: project_id)

    render json: { ok: true }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#clear_client_links] #{e.class} - #{e.message}")
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

  # Paso "links de equipos externos" (alta): inserta filas de respondientes
  # NUEVAS (samplenumber/clientlinkid/clientlink/equipo/email2) via
  # el servicio surveydata (endpoint SIN confirmar todavia por Forsta
  # soporte, inferido por patron -- ver ConfirmitSoapClient::SURVEYDATA_ENDPOINT).
  # Es un alta (append), no un update -- ver ConfirmitSoapClient#append_respondents.
  # rows viene ya armado del lado del cliente (ver buildExternalTeamRows en
  # el wizard) -- este endpoint solo lo manda a Confirmit, en tandas de 500
  # (mismo limite que ya usa upload_client_links).
  def append_respondents
    project_id = params[:project_id].to_s.strip
    rows = params.permit(rows: %i[samplenumber clientlinkid clientlink equipo equipopais email2])[:rows].to_a.map { |row| row.to_h }

    if project_id.blank? || rows.empty?
      return render json: { ok: false, error: 'project_id y rows son obligatorios' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    rows.each_slice(500) { |batch| client.append_respondents(project_id: project_id, rows: batch) }

    render json: { ok: true, count: rows.length }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#append_respondents] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Paso "links de equipos externos" (update): escribe "equipolink" (el link
  # final, armado del lado del cliente con surveylink+&l=/&contacto=) en
  # filas que YA EXISTEN, identificadas por su respid real -- ver
  # ConfirmitSoapClient#update_respondents_by_respid. Cada row DEBE incluir
  # :respid (traido de un read_respondents_links anterior).
  # IMPORTANTE: hay que mandar TODOS los campos de la fila, no solo
  # respid+equipolink -- confirmado 2026-09-09 que un update marcado
  # diffgr:hasChanges="modified" con solo un par de campos hace que
  # Confirmit trate esa fila como "asi queda completa" y borra el resto
  # (samplenumber/equipo/email2/clientlink/clientlinkid/equipopais, que el
  # alta SI habia escrito bien).
  def update_respondent_links
    project_id = params[:project_id].to_s.strip
    permitted_fields = %i[respid samplenumber clientlinkid clientlink equipo equipopais email2 equipolink]
    rows = params.permit(rows: permitted_fields)[:rows].to_a.map { |row| row.to_h }

    if project_id.blank? || rows.empty?
      return render json: { ok: false, error: 'project_id y rows son obligatorios' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    rows.each_slice(500) { |batch| client.update_respondents_by_respid(project_id: project_id, rows: batch) }

    render json: { ok: true, count: rows.length }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#update_respondent_links] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Lee de vuelta las filas de respondientes de un proyecto (con el respid y
  # el link real de encuesta generado por Confirmit por fila,
  # GenerateSurveyLink=true) -- usado despues de append_respondents para
  # obtener el respid real de las filas recien insertadas y poder armar el
  # link final (surveylink + &l=... + &contacto=...), que despues se pisa en
  # "clientlink" via update_respondent_links (identificando cada fila por su
  # respid). Trae TODOS los respondientes del proyecto (la API no soporta
  # filtrar por lista de IDs) -- el filtrado por email2 lo hace el wizard
  # del lado del cliente.
  def read_respondents_links
    project_id = params[:project_id].to_s.strip
    # Default true (comportamiento de siempre, usado por la generacion de
    # links de equipos externos). false para el Analisis del Proyecto (solo
    # lectura de metricas de campo) -- no hace falta que Confirmit genere un
    # link por fila para eso, y con proyectos grandes (5000+ respondents)
    # evita trabajo de mas. Pedido del usuario 2026-09-14.
    generate_survey_link = params.key?(:generate_survey_link) ? ActiveModel::Type::Boolean.new.cast(params[:generate_survey_link]) : true

    if project_id.blank?
      return render json: { ok: false, error: 'project_id es obligatorio' }, status: :unprocessable_entity
    end

    client = ::FinePanelSetup::ConfirmitSoapClient.new
    rows = client.get_respondents(project_id: project_id, generate_survey_link: generate_survey_link)

    render json: { ok: true, rows: rows }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#read_respondents_links] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # CRUD de proveedores/equipos (TeamContact) -- reemplaza el array fijo
  # TEAM_CONTACTS que antes vivia hardcodeado en el wizard. Tabla real (no
  # localStorage/archivo) para que sea compartida entre todos los usuarios y
  # sobreviva a los deploys -- ver migracion CreateTeamContacts, 2026-09-09.
  def team_contacts_index
    contacts = TeamContact.order(:pais1_rec_code, :name)
    render json: { ok: true, contacts: contacts.as_json(only: %i[id name pais1_rec_code paga_fine]) }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#team_contacts_index] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  def team_contacts_create
    contact = TeamContact.new(
      name: params[:name].to_s.strip.upcase,
      pais1_rec_code: params[:pais1_rec_code].to_s.strip,
      paga_fine: ActiveModel::Type::Boolean.new.cast(params[:paga_fine])
    )

    if contact.save
      render json: { ok: true, contact: contact.as_json(only: %i[id name pais1_rec_code paga_fine]) }
    else
      render json: { ok: false, error: contact.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#team_contacts_create] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  def team_contacts_destroy
    contact = TeamContact.find_by(id: params[:id])
    return render json: { ok: false, error: 'No encontrado' }, status: :not_found unless contact

    contact.destroy
    render json: { ok: true }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#team_contacts_destroy] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Valores por default de incentivo (IncentiveRate) -- reemplaza las tablas
  # fijas SUGGESTED_VALUE_TABLE/TEAM_INCENTIVE_TABLE_BRASIL que antes vivian
  # hardcodeadas en el wizard. Tabla real (no localStorage) para que sea
  # compartida entre todos los usuarios y sobreviva a los deploys -- ver
  # migracion CreateIncentiveRates, 2026-09-10.
  def incentive_rates_index
    rates = IncentiveRate.order(:category, :max_minutes, :currency)
    render json: { ok: true, rates: rates.as_json(only: %i[id category max_minutes currency value]) }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#incentive_rates_index] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # Actualiza varias celdas de una sola vez (una tabla entera por vez desde
  # el frontend, ver #incentiveRatesSaveBtn) -- no crea/borra filas, el set de
  # category+max_minutes+currency posibles es fijo (definido por la
  # migracion), esto solo pisa el "value" de las que ya existen.
  def incentive_rates_bulk_update
    updates = params.permit(rates: %i[category max_minutes currency value])[:rates].to_a
    updated = 0

    ActiveRecord::Base.transaction do
      updates.each do |u|
        rate = IncentiveRate.find_by(category: u[:category], max_minutes: u[:max_minutes], currency: u[:currency].to_s)
        next unless rate

        rate.update!(value: u[:value])
        updated += 1
      end
    end

    render json: { ok: true, count: updated }
  rescue StandardError => e
    Rails.logger.error("[FinePanelSetup::SetupController#incentive_rates_bulk_update] #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  # Mismo patron que Api::V1::ApiController#resolve_jwt_token: no valida la
  # firma del JWT, solo lee el claim "jti" y lo busca en la tabla -- el jti
  # en si (uuid random, unico, rotado en cada login) es el secreto real
  # siendo chequeado, no la firma del token. No se usa warden.authenticate!
  # aca por la misma razon que en InternalUsers::SessionsController.
  def authenticate_via_jwt!
    @current_internal_user = internal_user_from_bearer

    render json: { ok: false, error: 'No autorizado' }, status: :unauthorized unless @current_internal_user
  end
end
