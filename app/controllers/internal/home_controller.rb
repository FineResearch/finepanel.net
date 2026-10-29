# frozen_string_literal: true

# Entrada comun a las herramientas internas (GET /internal): login unico y
# menu de recursos (Wizard, inbox de WhatsApp, Automated Transcripts). Sirve
# solo el cascaron estatico; el login y la validacion del token los hace la
# pagina contra POST /internal/auth/login y GET /internal/auth/whoami.
class Internal::HomeController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    render file: Rails.root.join('public', 'internal-home', 'index.html'), layout: false
  end
end
