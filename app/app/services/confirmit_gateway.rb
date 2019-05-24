# frozen_string_literal: true

require 'net/http'
require 'configuration_reader'

class ConfirmitGateway
  class << self
    def new_account(params)
      sanitized_params = sanitize_params_for_create(params)
      create_account_url = "https://survey.finepanel.net//wix/p785267057.aspx?#{sanitized_params.to_query}"

      response = Net::HTTP.post_form(URI(create_account_url), 'q' => 'ruby', 'max' => '50')
      user_params = values_from_html(response.body)
      sanitize_user_params(params, user_params)
    end

    def get_surveys_for_user(user, respid)
      user_url = user_profile_url(user, respid)
      response = Net::HTTP.post_form(URI(user_url), 'q' => 'ruby', 'max' => '50')
      surveys = get_surveys_from_response(response.body).to_a

      get_active_surveys_for_user(surveys)
    end

    def get_payments_for_user(user_data)
      {
        total_payments: user_data[:totalpagos],
        credit: user_data[:credito],
        total: (user_data[:totalpagos].to_i + user_data[:credito].to_i).to_s
      }
    end

    def get_participations_for_user(user_data)
      last_participations = []
      1.upto(5) do |i|
        next unless user_data["detalle#{i}"].present?

        survey_detail = user_data["detalle#{i}"].split('*')
        participation = {
          project: survey_detail[0],
          status: survey_detail[1],
          fee: survey_detail[2],
          payment_date: survey_detail[3],
          date: I18n.l(user_data["datapart#{i}"].to_time, format: :participation_date)
        }
        last_participations << participation
      end
      last_participations
    end

    def get_user_attrs_from_profile(url)
      response = Net::HTTP.post_form(URI(url), 'q' => 'ruby', 'max' => '50')

      p_list = Nokogiri::HTML.parse(response.body).xpath('//p')
      return nil unless p_list[1].present?
      return nil unless p_list[1].children[0].present?

      attrs = p_list[1].children[0].text.split('&').map { |user_attr| user_attr.split('=') }
      Hash[attrs.map { |key, value| [key, value] }]
    end

    def user_profile_url(user, respid)
      user.user_profile_url(respid)
    end

    def get_currency_for_user(user_data)
      ConfigurationReader.currency(user_data[:country_id])
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
        next if survey_link.blank?

        survey_data = survey_link.data_from_valid_survey
        next unless survey_data.present?

        survey[:link] = survey_link.link

        survey[:name] = survey_data[:name]
        survey[:subject] = survey_data[:subject]
        survey[:duration] = survey_data[:duration]
        survey[:fee] = survey_data[:fee]
        survey[:priority] = survey_data[:priority]

        result << survey
      end.compact

      first_priority_surveys = result.select { |survey| survey[:priority] == '1' }
      return first_priority_surveys if first_priority_surveys.present?

      result.sort_by { |survey| survey['priority'] }
    end

    def valid_survey_link?(link)
      response = Net::HTTP.post_form(URI(link), 'q' => 'ruby', 'max' => '50')
      response.body.downcase.include?('legalmente') && response.code != 404
    end

    def data_from_valid_survey(link)
      response = Net::HTTP.post_form(URI(link), 'q' => 'ruby', 'max' => '50')
      return nil unless response.body.downcase.include?('legalmente') && response.code != 404

      survey_data = Nokogiri::HTML.parse(response.body).xpath('//div[@id="Filtro_text"]').children[0].children[0]
      sanitize_data_from_survey(survey_data)
    end

    def sanitize_data_from_survey(survey_data)
      {
        name: survey_data.children[1].text.split(': ')[1],
        subject: survey_data.children[2].text.split(': ')[1],
        duration: survey_data.children[4].text.split(': ')[1],
        fee: survey_data.children[5].text.split(': ')[1],
        priority: survey_data.children[6].text.split(': ')[1]
      }
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
