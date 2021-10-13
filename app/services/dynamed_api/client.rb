require 'net/http'

module DynamedApi
  class Client
    attr_reader :token

    BASE_HOST     = ENV['API_DYNAMED_URL'] || 'https://apis.ebsco.com'
    CLIENT_ID     = ENV['DYNAMED_CLIENT_ID'] || 'client_id'
    CLIENT_SECRET = ENV['DYNAMED_CLIENT_SECRET'] || 'client_secret'
    TOKEN_PATH    = '/medsapi-auth/v1/token'

    def initialize(endpoint)
      @endpoint = endpoint
    end

    def process
      return nil unless @endpoint.present?
      @token = request_token
      return nil unless token.present?
      get_api_information
    end

    private

    def get_api_information
      uri = URI("#{BASE_HOST}#{@endpoint}")

      http = set_http_obj(uri.host, uri.port)

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{@token}"
      request["Content-Type"] = "application/json"

      response = http.request(request)
      response.code == '200' ? JSON.parse(response.body) : nil
    end

    def request_token
      uri = URI("#{BASE_HOST}#{TOKEN_PATH}")

      req = Net::HTTP::Post.new(uri)
      req.body = { grant_type: 'client_credentials', product: 'dynamed', client_id: CLIENT_ID, client_secret: CLIENT_SECRET}.to_json

      http = set_http_obj(uri.host, uri.port)

      response = http.request(req)
      response.code == '200' ? JSON.parse(response.body)['access_token'] : nil
    end

    def set_http_obj(host, port)
      obj = Net::HTTP.new(host, port)
      obj.use_ssl = true
      obj.verify_mode = OpenSSL::SSL::VERIFY_NONE

      obj
    end
  end
end
