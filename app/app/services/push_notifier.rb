# frozen_string_literal: true
require 'net/http'

class PushNotifier
  SERVICE_ENDPOINT = 'https://fineresearch.myqmob.com/reactor-webapp/pt/'
  PROJECT_NOTIFICATIONS = 'lumi_say/pn/lumicompass/api/send_notifications'

  def initialize(users, message)
    @users = users
    @message = message
  end

  def send_notification
    respondents = @users.map { |user| { username: user } }

    respondents_json = {
      message: @message,
      respondents: respondents
    }

    notifications_uri = URI(notifications_url)
    query_params = format_query_params(respondents_json)

    Net::HTTP.post_form(notifications_uri, query_params)
  end

  private

  def notifications_url
    "#{SERVICE_ENDPOINT}#{PROJECT_NOTIFICATIONS}"
  end

  def format_query_params(respondents_json)
    {
      user_name: ENV['API_USERNAME'],
      password: ENV['API_PASSWORD'],
      respondents_json: respondents_json.to_json,
    }
  end
end
