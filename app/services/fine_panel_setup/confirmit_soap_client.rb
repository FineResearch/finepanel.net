# frozen_string_literal: true

require 'net/http'
require 'uri'

module FinePanelSetup
  class ConfirmitSoapClient
    LOGON_ENDPOINT = ENV.fetch(
      'CONFIRMIT_LOGON_ENDPOINT',
      'https://author.us.confirmit.com/confirmit/webservices/current/logon.asmx'
    )

    def log_on
      username = ENV['CONFIRMIT_API_USERNAME']
      password = ENV['CONFIRMIT_API_PASSWORD']
      raise 'CONFIRMIT_API_USERNAME/CONFIRMIT_API_PASSWORD no configurados' if username.blank? || password.blank?

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

      response_body = post_soap(
        endpoint: LOGON_ENDPOINT,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/LogOnUser',
        envelope: envelope
      )

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!
      result = doc.at_xpath('//LogOnUserResult')
      fault = doc.at_xpath('//Fault')

      raise "Confirmit LogOnUser fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}" if fault
      raise 'Confirmit LogOnUser no devolvio una clave de autorizacion' if result.nil? || result.text.blank?

      result.text
    end

    # Namespace y forma del request/response confirmados contra el WSDL real (Forsta soporte, 2026-08-19):
    # https://horizons.confirmit.eu/confirmit/webservices/current/authoring.asmx?wsdl
    # El host es el que Forsta nos paso directo (EU) -- no el "author.us.confirmit.com" que funciona
    # para LogOnUser; ese host devolvia error para authoring.asmx/surveydesign.asmx en todas las pruebas.
    AUTHORING_ENDPOINT = ENV.fetch(
      'CONFIRMIT_AUTHORING_ENDPOINT',
      'https://horizons.confirmit.eu/confirmit/webservices/current/authoring.asmx'
    )

    def duplicate_project(source_project_id:, new_project_name:)
      key = log_on

      envelope = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <DuplicateProject xmlns="http://firmglobal.com/Confirmit/webservices/">
              <key>#{key}</key>
              <projectId>#{source_project_id}</projectId>
              <newProjectName>#{new_project_name}</newProjectName>
            </DuplicateProject>
          </soap:Body>
        </soap:Envelope>
      XML

      response_body = post_soap(
        endpoint: AUTHORING_ENDPOINT,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/DuplicateProject',
        envelope: envelope
      )

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!
      result = doc.at_xpath('//DuplicateProjectResult')
      fault = doc.at_xpath('//Fault')

      if fault
        { ok: false, error: fault.at_xpath('.//faultstring')&.text || fault.text }
      elsif result && result.text.present?
        { ok: true, project_id: result.text }
      else
        { ok: false, error: "Respuesta inesperada: #{response_body[0, 300]}" }
      end
    end

    private

    def post_soap(endpoint:, soap_action:, envelope:)
      uri = URI.parse(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'text/xml; charset=utf-8'
      request['SOAPAction'] = soap_action
      request.body = envelope

      http.request(request).body
    end
  end
end
