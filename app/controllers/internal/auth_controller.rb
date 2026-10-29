# frozen_string_literal: true

# Shared introspection endpoint for internal tools that live outside this
# app (e.g. Automated Transcripts, on its own AWS infra -- see that repo's
# api/auth.py). Same token check as the Wizard and the WhatsApp inbox (see
# InternalJwtAuthentication), exposed as a standalone endpoint so another
# service can reuse the shared login without needing this app's JWT signing
# secret or DB access.
class Internal::AuthController < ApplicationController
  include InternalJwtAuthentication

  skip_before_action :verify_authenticity_token

  def whoami
    user = internal_user_from_bearer

    return render json: { error: 'Unauthorized' }, status: :unauthorized unless user

    render json: { email: user.email, role: user.role }
  end
end
