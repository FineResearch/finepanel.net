# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery
  before_action :set_locale

  def set_locale
    params[:locale] ||= cookies[:locale] ||= extract_locale_from_accept_language_header
    I18n.locale = cookies[:locale] = params[:locale]
  end

  def default_url_options(_options = {})
    { locale: cookies[:locale] || I18n.locale }
  end

  def current_user
    user = super
    user.email = session[:user_email] if user.present?
    user
  end

  protected

  def after_sign_in_path_for(resource)
    session[:respid] = resource.user_respid(resource.email)
    session[:user_email] = resource.email
    super
  end

  private

  def extract_locale_from_accept_language_header
    request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^(es|pt)/).first.first
  rescue StandardError
    'pt'
  end
end
