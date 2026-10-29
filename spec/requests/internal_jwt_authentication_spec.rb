# frozen_string_literal: true

require 'rails_helper'

# Login comun de las herramientas internas (ver InternalJwtAuthentication): el
# mismo Bearer token, verificado, abre el Wizard, el inbox de WhatsApp y
# Automated Transcripts (via /internal/auth/whoami).
RSpec.describe 'login comun de herramientas internas' do
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) do
    InternalUser.create!(email: 'admin@fine-research.com', password: 'Password123!', role: 'admin', active: true)
  end

  let(:json_headers) { { 'Accept' => 'application/json' } }

  def login_token
    post '/internal/auth/login', params: { internal_user: { email: user.email, password: 'Password123!' } }, as: :json
    response.headers['Authorization']
  end

  def forged_token
    JWT.encode({ 'jti' => user.jti }, 'otro-secreto', 'HS256')
  end

  describe 'inbox de WhatsApp (GET /internal/whatsapp/conversations)' do
    it 'acepta el Bearer token del login comun' do
      get '/internal/whatsapp/conversations', headers: json_headers.merge('Authorization' => login_token)

      expect(response).to have_http_status(:ok)
    end

    it 'ya no acepta el email suelto en la cabecera' do
      get '/internal/whatsapp/conversations', headers: json_headers.merge('X-Internal-User-Email' => user.email)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'ya no acepta el email suelto en la URL' do
      get '/internal/whatsapp/conversations', params: { internal_user_email: user.email }, headers: json_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza sin credenciales' do
      get '/internal/whatsapp/conversations', headers: json_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza un token con jti valido pero firmado con otro secreto' do
      get '/internal/whatsapp/conversations', headers: json_headers.merge('Authorization' => "Bearer #{forged_token}")

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza si el usuario esta inactivo' do
      token = login_token
      user.update!(active: false)

      get '/internal/whatsapp/conversations', headers: json_headers.merge('Authorization' => token)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'la descarga del export tambien exige el Bearer token' do
      get '/internal/whatsapp/conversations/export', headers: json_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'Wizard (POST /internal/fine_panel_setup/team_contacts_list)' do
    it 'acepta el Bearer token del login comun' do
      post '/internal/fine_panel_setup/team_contacts_list', headers: json_headers.merge('Authorization' => login_token), as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'rechaza sin token' do
      post '/internal/fine_panel_setup/team_contacts_list', headers: json_headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza un token falsificado' do
      post '/internal/fine_panel_setup/team_contacts_list', headers: json_headers.merge('Authorization' => "Bearer #{forged_token}"), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'whoami (GET /internal/auth/whoami)' do
    it 'acepta un token emitido por el login real' do
      get '/internal/auth/whoami', headers: { 'Authorization' => login_token }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq('email' => 'admin@fine-research.com', 'role' => 'admin')
    end

    it 'rechaza un token vencido' do
      token = login_token

      travel_to(8.days.from_now) do
        get '/internal/auth/whoami', headers: { 'Authorization' => token }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'rechaza un token falsificado' do
      get '/internal/auth/whoami', headers: { 'Authorization' => "Bearer #{forged_token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza sin cabecera Authorization' do
      get '/internal/auth/whoami'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza basura en vez de un JWT' do
      get '/internal/auth/whoami', headers: { 'Authorization' => 'Bearer esto-no-es-un-jwt' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'paginas (cascarones estaticos, sin datos)' do
    it 'sirve el ingreso comun en /internal' do
      get '/internal'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Herramientas internas')
    end

    it 'sirve el inbox sin credenciales: la autenticacion la resuelve la API' do
      get '/internal/whatsapp/inbox'

      expect(response).to have_http_status(:ok)
    end

    it 'sigue sirviendo el Wizard y Transcripciones' do
      get '/internal/fine_panel_setup'
      expect(response).to have_http_status(:ok)

      get '/internal/automated_transcripts'
      expect(response).to have_http_status(:ok)
    end
  end

  it 'el login existente no se ve afectado: POST /internal/auth/login emite un JWT' do
    post '/internal/auth/login', params: { internal_user: { email: user.email, password: 'Password123!' } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.headers['Authorization']).to start_with('Bearer ')
  end
end
