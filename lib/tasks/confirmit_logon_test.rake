# frozen_string_literal: true

require 'net/http'
require 'uri'

# Chequeo minimo, de solo lectura: confirma que CONFIRMIT_API_USERNAME/CONFIRMIT_API_PASSWORD
# son validos llamando a LogOnUser (SOAP). No crea ni modifica nada en Confirmit.
#
# Uso: bin/rails confirmit:logon_test
namespace :confirmit do
  task logon_test: :environment do
    username = ENV['CONFIRMIT_API_USERNAME']
    password = ENV['CONFIRMIT_API_PASSWORD']

    if username.blank? || password.blank?
      puts 'Faltan CONFIRMIT_API_USERNAME / CONFIRMIT_API_PASSWORD en el .env local.'
      next
    end

    endpoint = ENV.fetch('CONFIRMIT_LOGON_ENDPOINT', 'https://author.us.confirmit.com/confirmit/webservices/current/logon.asmx')
    uri = URI.parse(endpoint)

    envelope = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <LogOnUser xmlns="http://firmglobal.com/Confirmit/webservices/">
            <username>#{username}</username>
            <password>#{password}</password>
          </LogOnUser>
        </soap:Body>
      </soap:Envelope>
    XML

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'text/xml; charset=utf-8'
    request['SOAPAction'] = 'http://firmglobal.com/Confirmit/webservices/LogOnUser'
    request.body = envelope

    response = http.request(request)

    puts "HTTP status: #{response.code}"

    doc = Nokogiri::XML(response.body)
    doc.remove_namespaces!
    result = doc.at_xpath('//LogOnUserResult')
    fault = doc.at_xpath('//Fault')

    if fault
      puts "SOAP fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}"
    elsif result && result.text.present?
      puts "Login OK. Authorization key (primeros 8 caracteres): #{result.text[0, 8]}..."
    else
      puts 'Respuesta inesperada:'
      puts response.body
    end
  end
end
