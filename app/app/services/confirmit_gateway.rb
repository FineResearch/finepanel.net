# frozen_string_literal: true

require 'net/http'
require 'configuration_reader'

class ConfirmitGateway
  class << self
    def new_account(params)
      sanitized_params = sanitize_params_for_create(params)
      params_for_create_user(params, sanitized_params)
    end

    def new_colleague(params)
      sanitized_params = sanitize_params_for_create_colleague(params)
      params_for_create_user(params, sanitized_params)
    end

    def update_user(respid, spanel, params)
      sanitized_params = sanitize_params_for_update(respid, spanel, params)
      update_user_data(sanitized_params)
    end

    def update_user_payment_data(respid, spanel, params)
      sanitized_params = sanitize_params_for_update_payment_data(respid, spanel, params)
      update_user_data(sanitized_params)
    end

    def params_for_create_user(params, sanitized_params)
      create_account_url = "https://survey.finepanel.net//wix/p785267057.aspx?#{sanitized_params.to_query}"

      response = Net::HTTP.post_form(URI(create_account_url), 'q' => 'ruby', 'max' => '50')
      user_params = values_from_html(response.body)
      sanitize_user_params(params, user_params)
    end

    def update_user_data(sanitized_params)
      create_account_url = "https://survey.finepanel.net/wix/p785267057.aspx?#{sanitized_params.to_query}"
      response = Net::HTTP.post_form(URI(create_account_url), 'q' => 'ruby', 'max' => '50')
      response.code == '200'
    end

    def get_surveys_for_user(user, respid)
      user_url = user_profile_url(user, respid)
      response = Net::HTTP.post_form(URI(user_url), 'q' => 'ruby', 'max' => '50')
      surveys = get_surveys_from_response(response.body).to_a

      if surveys.any?
        language_param = user.language_param(respid)
        survey_list = get_active_surveys_for_user(surveys, language_param)
        add_next_surveys_to_links(survey_list)
      else
        []
      end
    end

    def get_surveys_for_redirect_to_portal(user, respid)
      user_url = user_profile_url(user, respid)
      response = Net::HTTP.post_form(URI(user_url), 'q' => 'ruby', 'max' => '50')
      surveys = get_surveys_from_response(response.body).to_a

      language_param = user.language_param(respid)
      survey_list = get_active_surveys_for_user(surveys, language_param)
      surveys_params_for_redirect_to_portal_link(survey_list)
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
          date: user_data["datapart#{i}"].to_time
        }
        last_participations << participation
      end

      sort_last_participations!(last_participations).each do |participation|
        participation[:date] = I18n.l(participation[:date], format: :participation_date)
      end
    end

    def sort_last_participations!(participations)
      participations.sort_by { |survey| survey[:date] }.reverse!
    end

    def get_user_attrs_from_profile(url)
      response = Net::HTTP.post_form(URI(url), 'q' => 'ruby', 'max' => '50')

      p_list = Nokogiri::HTML.parse(response.body).xpath('//p')
      return nil unless p_list[1].present?
      return nil unless p_list[1].children[0].present?

      attrs = p_list[1].children[0].text.split('&').map { |user_attr| user_attr.split('=') }
      Hash[attrs.map { |key, value| [key, value] }].with_indifferent_access
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

    def get_active_surveys_for_user(surveys, language_param)
      or_conditions = []
      surveys.each do |survey|
        next unless survey[:project_id].starts_with?('p') && survey[:resp_id].present?
        or_conditions << "(survey_links.project_id = '#{survey[:project_id]}' AND survey_links.resp_id = '#{survey[:resp_id]}')"
      end

      return [] if or_conditions.empty?

      survey_links = SurveyLink.where(or_conditions.join(' OR '))
      survey_links = survey_links.group_by(&:project_id)
      valid_surveys(surveys, survey_links, language_param)
    end

    def valid_surveys(surveys, survey_links, language_param)
      result = []
      surveys.each do |survey|
        survey_link  = survey_links[survey[:project_id]]&.first
        next if survey_link.blank?

        survey_data = survey_link.data_from_valid_survey(language_param)
        next unless survey_data.present?

        survey[:link] = survey_link.link + '&l=' + language_param
        survey[:name] = survey_data[:name]
        survey[:subject] = survey_data[:subject]
        survey[:profile] = survey_data[:profile]
        survey[:duration] = survey_data[:duration]
        survey[:fee] = survey_data[:fee]
        survey[:priority] = survey_data[:priority]
        survey[:status] = survey_data[:status]

        survey[:project_id] = survey[:link].match(%r{/(p\d*).})[1]
        survey[:respid] = survey[:link].match(/r=(.*?)&/)[1]
        survey[:spanel] = survey[:link].match(/s=(.*?)&/)[1]

        result << survey
      end.compact

      first_priority_surveys = result.select { |survey| survey[:priority] == '1' }
      return first_priority_surveys if first_priority_surveys.present?

      result.sort_by { |survey| survey[:priority] }
    end

    def valid_survey_link?(link)
      response = Net::HTTP.post_form(URI(link), 'q' => 'ruby', 'max' => '50')
      response.body.downcase.include?('legalmente') && response.code != 404
    end

    def data_from_valid_survey(link, language_param)
      response = Net::HTTP.post_form(URI(link + '&l=' + language_param), 'q' => 'ruby', 'max' => '50')
      return nil unless response.body.downcase.include?('legalmente') && response.code != 404

      survey_data = get_survey_data_from_response(response.body, language_param)
      return nil unless survey_data.present?

      check_empty_values(survey_data)
    end

    def get_survey_data_from_response(raw_response, language_param)
      survey_data = Nokogiri::HTML.parse(raw_response).css('#Filtro_text')

      return survey_data_from_initiated_survey(raw_response, language_param) unless survey_data.present?
      return sanitize_data_from_survey_lang_pt(survey_data.children[0].children[0]) if language_pt?(language_param)
      return nil unless survey_data.children[1].children[0].present?

      sanitize_data_from_survey_lang_es(survey_data.children[1].children[0].children[0])
    end

    def survey_data_from_initiated_survey(raw_response, language_param)
      survey_data = Nokogiri::HTML.parse(raw_response).css('#avisodeinc_text')
      return sanitize_data_from_initiated_survey_pt(survey_data) if language_pt?(language_param)
      sanitize_data_from_initiated_survey_es(survey_data)
    end

    def sanitize_data_from_survey_lang_pt(survey_data)
      {
        name: sanitize_survey_attribute(survey_data.children[1]),
        subject: sanitize_survey_attribute(survey_data.children[2]),
        profile: sanitize_survey_attribute(survey_data.children[3]),
        duration: sanitize_survey_attribute(survey_data.children[4]),
        fee: sanitize_survey_attribute(survey_data.children[5]),
        priority: sanitize_survey_attribute(survey_data.children[6]),
        status: ConfigurationReader.status_new_survey
      }
    end

    def sanitize_data_from_survey_lang_es(survey_data)
      {
        name: sanitize_survey_attribute(survey_data.children[0]),
        subject: sanitize_survey_attribute(survey_data.children[1]),
        profile: sanitize_survey_attribute(survey_data.children[2]),
        duration: sanitize_survey_attribute(survey_data.children[3]),
        fee: sanitize_survey_attribute(survey_data.children[4]),
        priority: sanitize_survey_attribute(survey_data.children[5]),
        status: ConfigurationReader.status_new_survey
      }
    end

    def sanitize_data_from_initiated_survey_pt(survey_data)
      {
        name: sanitize_survey_attribute(survey_data.children[0]),
        subject: sanitize_survey_attribute(survey_data.children[1]),
        profile: sanitize_survey_attribute(survey_data.children[2]),
        duration: sanitize_survey_attribute(survey_data.children[3]),
        fee: sanitize_survey_attribute(survey_data.children[4]),
        priority: sanitize_survey_attribute(survey_data.children[5]),
        status: ConfigurationReader.status_initiated_survey
      }
    end

    def sanitize_data_from_initiated_survey_es(survey_data)
      {
        name: sanitize_survey_attribute(survey_data.children[1]),
        subject: sanitize_survey_attribute(survey_data.children[2]),
        profile: sanitize_survey_attribute(survey_data.children[3]),
        duration: sanitize_survey_attribute(survey_data.children[4]),
        fee: sanitize_survey_attribute(survey_data.children[5]),
        priority: sanitize_survey_attribute(survey_data.children[6]),
        status: ConfigurationReader.status_initiated_survey
      }
    end



    def check_empty_values(data)
      data.select { |_, v| v.nil? || v == '' }.blank? ? data : nil
    end

    def sanitize_survey_attribute(attribute)
      return '' unless attribute.present?

      sanitized_attribute = attribute.text.split(': ')[1]
      sanitized_attribute.strip.delete("\u00A0") if sanitized_attribute.present?
    end

    def surveys_params_for_redirect_to_portal_link(surveys)
      surveys.map.with_index(1){|survey, index| next_survey_params(survey, index)}.reduce(:+)
    end

    def add_next_surveys_to_links(surveys)
      surveys.each_with_index do |_survey, i|
        (1..5).each do |n|
          break if surveys[i + n].blank?

          surveys[i][:link] += next_survey_params(surveys[i + n], n)
        end
      end
    end

    def next_survey_params(next_survey, n)
      params = ''
      params += "&RFP#{n}=" + next_survey[:name].tr(' ', '+')
      params += "&Rasunto#{n}=" + next_survey[:subject].tr(' ', '+')
      params += "&Rperfil#{n}=" + next_survey[:profile].tr(' ', '+')
      params += "&Rdura#{n}=" + next_survey[:duration].tr(' ', '+')
      params += "&Rhono#{n}=" + next_survey[:fee].tr(' ', '+')
      params += "&Rp#{n}=" + next_survey[:project_id]
      params += "&Rrespid#{n}=" + next_survey[:respid]
      params += "&Rs#{n}=" + next_survey[:spanel]
      params += "&Rstatus#{n}=" + next_survey[:status]
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

    def sanitize_params_for_update(respid, spanel, params)
      {
        r: respid,
        s: spanel,
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
        exit: 'updateportal'
      }
    end

    def sanitize_params_for_create_colleague(params)
      {
        emailr: params[:email],
        namer: params[:first_name],
        apellidor: params[:last_name],
        titulor: params[:suffix],
        espr: params[:specialty_id],
        pais: params[:country_id],
        exit: 'updateportal',
        fuente: params[:fuente]
      }
    end

    def sanitize_params_for_update_payment_data(respid, spanel, params)
      b1 = User.bank_account_type_param(params[:bank_account_type])
      b5 = params[:bank_account_owner] == 'true' ? '1' : '2'
      b6 = params[:bank_account_owner] == 'true' ? ' ' : params[:bank_account_name]

      {
        r: respid,
        s: spanel,
        B1: b1,
        B2: params[:bank_name],
        B3: params[:bank_branch],
        B4: params[:bank_account_number],
        B5: b5,
        B6: b6,
        exit: 'updatepagos'
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

    def language_pt?(language)
      language == ConfigurationReader.language_code('1')
    end
  end
end
