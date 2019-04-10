# frozen_string_literal: true

class ApplicationController < ActionController::Base
  before_action :set_locale

  def set_locale
    params[:locale] ||= cookies[:locale] ||= extract_locale_from_accept_language_header
    I18n.locale = cookies[:locale] = params[:locale]
  end

  def default_url_options(_options = {})
    { locale: cookies[:locale] || I18n.locale }
  end

  private

  def extract_locale_from_accept_language_header
    request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^(es|pt)/).first.first
  rescue StandardError
    'pt'
  end
end
