# frozen_string_literal: true

# Shared introspection endpoint for internal tools that live outside this
# app (e.g. Automated Transcripts, on its own AWS infra -- see that repo's
# api/auth.py). Same jti-against-InternalUser check as
# Internal::FinePanelSetup::SetupController#authenticate_via_jwt!, exposed
# as a standalone endpoint so another service can reuse the Wizard's login
# without needing this app's JWT signing secret or DB access.
class Internal::AuthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def whoami
    return render json: { error: 'Unauthorized' }, status: :unauthorized unless request.authorization.present?

    token = request.authorization.to_s.split('Bearer ').last
    jti = JWT.decode(token, nil, false).first['jti'] rescue nil
    user = InternalUser.active.find_by(jti: jti)

    return render json: { error: 'Unauthorized' }, status: :unauthorized unless user

    render json: { email: user.email, role: user.role }
  end
end
