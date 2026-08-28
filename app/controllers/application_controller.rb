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
    user.email = cookies[:user_email] if user.present?
    user
  end

  protected

  def after_sign_in_path_for(resource)
    return super unless resource.is_a?(User)

    expires_at = resource.remember_me.present? ? Devise.remember_for : nil
    cookies[:user_email] = { value: resource.email, expires: expires_at }
    cookies[:respid] = { value: resource.user_respid(resource.email), expires: expires_at }
    user_data = resource.profile_data_from_email(resource.email)
    cookies[:currency] = ConfirmitGateway.get_currency_for_user(user_data)
    cookies[:country_id] = user_data[:country_id]
    cookies[:locale] = ConfigurationReader.language(user_data[:country_id])
    super
  end

  def after_sign_out_path_for(resource)
    cookies.delete :user_email
    cookies.delete :respid
    super
  end

  private

  def extract_locale_from_accept_language_header
    request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^(es|pt)/).first.first
  rescue StandardError
    'pt'
  end
end
