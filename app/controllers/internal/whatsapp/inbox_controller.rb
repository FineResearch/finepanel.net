# frozen_string_literal: true

class Internal::Whatsapp::InboxController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_internal_access!

  def index
    render file: Rails.root.join('public', 'whatsapp-inbox', 'index.html'), layout: false
  end

  private

  def authenticate_internal_access!
    return if header_internal_user_present_and_active?

    render plain: 'Unauthorized', status: :unauthorized
  end

  def header_internal_user_present_and_active?
    email =
      request.headers['X-Internal-User-Email'].presence ||
      params[:internal_user_email].presence

    return false if email.blank?

    InternalUser.active.exists?(email: email.to_s.strip.downcase)
  end
end
