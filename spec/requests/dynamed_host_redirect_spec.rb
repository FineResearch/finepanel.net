# frozen_string_literal: true

require 'rails_helper'

# El frontend abre https://dynamed.finepanel.net (la RAIZ) para validar la
# sesion de DynaMed -- EBSCO no acepta un destino posterior sin login
# previo, por eso el flujo es en 2 pasos. Antes, el redirect solo cubria
# '*path', que no matchea la raiz: caia a la raiz normal de la app con host
# dynamed y devolvia 500.
RSpec.describe 'redirect del host dynamed' do
  let(:service_url) { 'https://search.ebscohost.com/login.aspx?authtype=ip,uid&custid=test&groupid=main&profile=dmp' }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SERVICE_URL').and_return(service_url)
    host! 'dynamed.finepanel.net'
  end

  it 'redirige la raiz al login de EBSCO' do
    get '/'

    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to eq(service_url)
  end

  it 'redirige cualquier otra ruta al mismo destino' do
    get '/cualquier/cosa'

    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to eq(service_url)
  end
end
