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

    def get_surveys_for_user(user)
      user_url = user_profile_url(user)
      response = Net::HTTP.post_form(URI(user_url), 'q' => 'ruby', 'max' => '50')
      surveys = get_surveys_from_response(response.body).to_a

      get_active_surveys_for_user(surveys)
    end

    def get_payments_for_user(user)
      user_url = user_profile_url(user)
      response = Net::HTTP.post_form(URI(user_url), 'q' => 'ruby', 'max' => '50')

      p_list = Nokogiri::HTML.parse(response.body).xpath('//p')
      return nil unless p_list[1].present?
      return nil unless p_list[1].children[0].present?

      parse_payment_attrs(p_list[1].children[0])
    end

    def parse_payment_attrs(attrs)
      user_attrs =  attrs.text.split('&').map { |user_attr| user_attr.split('=') }
      total_payments = user_attrs.select { |attr| attr[0] == 'totalpagos' }[0]
      credit = user_attrs.select { |attr| attr[0] == 'credito' }[0]
      total = total_payments[1].to_i + credit[1].to_i
      {
        total_payments: total_payments[1],
        credit: credit[1],
        total: total.to_s
      }
    end

    def user_profile_url(user)
      user.user_profile_url(user.email)
    end

    def get_surveys_from_response(raw_response)
      p_list = Nokogiri::HTML.parse(raw_response).xpath('//p')
      return nil unless p_list[2].present?
      return nil unless p_list[2].children[0].present?

      parse_projects_attrs(p_list[2].children[0])
    end

    def parse_projects_attrs(projects)
      projects.text.split('///').map { |survey| survey.split(';') }.map do |survey|
        {
          project_id: survey[0],
          name: survey[3],
          resp_id: survey[5]
        }
      end
    end

    def get_active_surveys_for_user(surveys)
      survey_links = SurveyLink.none
      surveys.each do |survey|
        survey_links = survey_links.or(SurveyLink.where(project_id: survey[:project_id], resp_id: survey[:resp_id]))
      end
      survey_links = survey_links.group_by(&:project_id)

      valid_surveys(surveys, survey_links)
    end

    def valid_surveys(surveys, survey_links)
      result = []
      surveys.each do |survey|
        survey_link  = survey_links[survey[:project_id]]&.first
        next if survey_link.blank? || !survey_link.valid_link?

        survey[:link] = survey_link.link
        result << survey
      end.compact
      result
    end

    def valid_survey_link?(link)
      response = Net::HTTP.post_form(URI(link), 'q' => 'ruby', 'max' => '50')
      response.body.downcase.include?('legalmente') && response.code != 404
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
