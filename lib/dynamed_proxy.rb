require 'rack-proxy'

class DynamedProxy < Rack::Proxy
  # Nota: no sobrecargamos initialize; Rack pasa (app, opts)
  def perform_request(env)
    request = Rack::Request.new(env)

    if request.host =~ %r{^dynamed}
      target = ENV['SERVICE_URL'] # e.g. https://dynamed.com/tokenlink?tokenId=...
      return [302, { 'Location' => target, 'Cache-Control' => 'no-cache' }, []]
    else
      @app.call(env)
    end
  end
end
