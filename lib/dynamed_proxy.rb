class DynamedProxy
  def initialize(app, _options = {})
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.host.to_s =~ %r{^dynamed}
      target = ENV['SERVICE_URL'].to_s
      return [302, { 'Location' => target, 'Cache-Control' => 'no-cache' }, []] if target.present?
    end

    @app.call(env)
  end
end
