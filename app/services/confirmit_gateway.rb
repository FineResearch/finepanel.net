# frozen_string_literal: true

require 'net/http'

class ConfirmitGateway
  class << self
    def new_account(params)
      sanitized_params = sanitize_params_for_create(params)
      create_account_url = "https://survey.finepanel.net//wix/p785267057.aspx?#{sanitized_params.to_query}"

      response = Net::HTTP.post_form(URI(create_account_url), 'q' => 'ruby', 'max' => '50')
      user_params = values_from_html(response.body)
      sanitize_user_params(params, user_params)
    end

    def sanitize_params_for_create(params)
      {
        emailr: params[:email],
        namer: params[:first_name],
        apellidor: params[:last_name],
        titulor: params[:suffix],
        espr: params[:specialty_id],
        pais: params[:country_id],
        telr: params[:phone],
        esp2r: params[:alternate_specialty_id],
        lugarr: params[:work_at_id],
        crmr: params[:crm],
        alternate_email: params[:alternate_email],
        city_id: params[:city_id],
        country_text: params[:country_text],
        city_text: params[:city_text],
        specialty_text: params[:specialty_text],
        exit: 'updateportal',
        fuente: 'RegistroPortal2019'
      }
    end

    def sanitize_user_params(params, user_params)
      {
        encrypted_email: Digest::MD5.hexdigest(params[:email]),
        hash_respid: user_params['r'].to_i + User.automated_password(params[:email]).to_i,
        spanel: user_params['s']
      }
    end

    def values_from_html(raw_response)
      document = Nokogiri::HTML.parse(raw_response)
      inputs = document.xpath('//input')
      inputs.select { |input| input['name'].in?(%w[r s]) }.map { |v| [v['name'], v['value']] }.to_h
    end
  end
end
