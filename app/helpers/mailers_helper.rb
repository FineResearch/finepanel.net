module MailersHelper
  def resolve_host
    ENV.fetch("APP_HOST", 'api.finepanel.net')
  end
end
