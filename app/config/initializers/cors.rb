Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins {ENV['APP_FRONTEND_URL'] || 'http://localhost:3001'}

    resource '*',
      headers: :any,
      methods: [:get]
  end
end
