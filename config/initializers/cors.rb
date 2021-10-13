Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins {ENV['APP_FRONTEND_URL'] || 'http://localhost:3001'}

    resource '*',
      headers: %w(Authorization),
      methods: :any,
      expose: %w(Authorization),
      max_age: 600
  end
end
