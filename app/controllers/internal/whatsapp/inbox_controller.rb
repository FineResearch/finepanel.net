# frozen_string_literal: true

# Sirve solo el cascaron estatico del inbox (sin datos), igual que el Wizard y
# Automated Transcripts: la autenticacion real la resuelve la API
# (Internal::Whatsapp::ConversationsController, con el Bearer token del login
# comun) y, si el token falta o vencio, el frontend redirige a /internal.
class Internal::Whatsapp::InboxController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    render file: Rails.root.join('public', 'whatsapp-inbox', 'index.html'), layout: false
  end
end
