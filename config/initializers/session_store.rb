if Rails.env.development?
  # Habilitado solo en development: las vistas HTML legacy (home#index,
  # devise sign_in) usan flash, que requiere sesion. En produccion se
  # mantiene deshabilitado (auth real es JWT).
  Rails.application.config.session_store :cookie_store, key: '_finepanel_session'
else
  Rails.application.config.session_store :disabled
end
