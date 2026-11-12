# frozen_string_literal: true

require 'rails_helper'

# Configuracion de envio del export por proyecto, cargada en el Wizard (ver
# ProjectExportSetting y Internal::FinePanelSetup::SetupController#export_settings_*).
RSpec.describe 'Wizard: envio de exports por proyecto' do
  let!(:user) do
    InternalUser.create!(email: 'pm@fine-research.com', password: 'Password123!', role: 'admin', active: true)
  end

  let(:token) do
    post '/internal/auth/login', params: { internal_user: { email: user.email, password: 'Password123!' } }, as: :json
    response.headers['Authorization']
  end

  let(:body) { "natalia@fine-research.com, priscila@iqvia.com\nQuotas:\nq0tipo: A=40; B=80\nReport:\nquotaregiao x q0tipo" }

  def api(action, payload = {})
    post "/internal/fine_panel_setup/#{action}", params: payload, headers: { 'Authorization' => token }, as: :json
    JSON.parse(response.body)
  end

  it 'exige el login comun (sin token da 401)' do
    post '/internal/fine_panel_setup/export_settings_list', as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'export_settings_save' do
    it 'guarda el texto con el ID normalizado, quien lo guardo, y devuelve lo que el sistema entendio' do
      json = api('export_settings_save', project_id: 'P588393362171', body: body)

      expect(response).to have_http_status(:ok)
      setting = json['setting']
      expect(setting['project_id']).to eq('p588393362171')
      expect(setting['updated_by']).to eq('pm@fine-research.com')
      expect(setting['preview']['recipients']).to eq(%w[natalia@fine-research.com priscila@iqvia.com])
      expect(setting['preview']['quotas'].first['variable']).to eq('q0tipo')
      expect(setting['preview']['reports'].first).to eq('variable_a' => 'quotaregiao', 'variable_b' => 'q0tipo')
    end

    it 'si ya existia, la actualiza (no duplica)' do
      api('export_settings_save', project_id: 'p588393362171', body: body)
      api('export_settings_save', project_id: 'p588393362171', body: 'otra@iqvia.com')

      expect(ProjectExportSetting.where(project_id: 'p588393362171').count).to eq(1)
      expect(ProjectExportSetting.for_project('p588393362171').recipients).to eq(%w[otra@iqvia.com])
    end

    it 'rechaza un ID que no es de Confirmit' do
      json = api('export_settings_save', project_id: 'FP-18874N', body: body)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to include('ID de Confirmit')
    end

    it 'rechaza un texto vacio' do
      api('export_settings_save', project_id: 'p588393362171', body: '   ')

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'export_settings_show / list / destroy' do
    before { api('export_settings_save', project_id: 'p588393362171', body: body) }

    it 'show devuelve el texto guardado' do
      json = api('export_settings_show', project_id: 'P588393362171')

      expect(json['setting']['body']).to eq(body)
    end

    it 'show de un proyecto sin configuracion devuelve setting nil' do
      expect(api('export_settings_show', project_id: 'p999999999')['setting']).to be_nil
    end

    it 'list resume cada proyecto con su cantidad de destinatarios' do
      json = api('export_settings_list')

      expect(json['settings'].map { |s| [s['project_id'], s['recipients_count']] }).to eq([['p588393362171', 2]])
    end

    it 'destroy la borra' do
      api('export_settings_destroy', project_id: 'p588393362171')

      expect(ProjectExportSetting.count).to eq(0)
    end

    it 'destroy de una inexistente da 404' do
      api('export_settings_destroy', project_id: 'p999999999')

      expect(response).to have_http_status(:not_found)
    end
  end
end
