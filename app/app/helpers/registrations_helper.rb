# frozen_string_literal: true

require 'configuration_reader'

module RegistrationsHelper
  def options_for_country_select(_resource = nil, country_id = nil)
    countries = ConfigurationReader.countries.map { |country| [t(country[0]), country[1]] }
    options_for_select(countries.sort, country_id)
  end

  def options_for_city_select(country_id = 1, city_id = nil)
    cities = ConfigurationReader.cities(country_id).map { |city| [t(city[0]), city[1]] }.sort
    if cities.blank?
      options_for_select([])
    else
      options_for_select(cities, city_id)
    end
  end

  def options_for_suffix_select(_resource = nil, suffix = nil)
    suffixes = ConfigurationReader.suffixes
    suffix[:selected] = suffix[:selected].split('.')[0] if suffix.present? && suffix[:selected].present?
    options_for_select(create_array_for_select(suffixes, 'suffixes.'), suffix)
  end

  def options_for_specialty_select(_resource = nil, specialty_id = nil)
    specialties = ConfigurationReader.specialties
    options_for_select(create_array_for_select(specialties, 'specialties.s'), specialty_id)
  end

  def options_for_work_at_select(_resource = nil, work_at_id = nil)
    work_at_options = ConfigurationReader.work_at_options
    options_for_select(create_array_for_select(work_at_options, 'work_at_options.w'), work_at_id)
  end

  def options_for_bank_account_type_select(bank_account_type = nil)
    bank_account_types = ConfigurationReader.bank_account_types.map { |type| [t("bank_account_types.#{type}"), type] }
    options_for_select(bank_account_types, bank_account_type)
  end

  def options_for_account_owner(bank_account_owner = nil)
    owner = bank_account_owner.present? && bank_account_owner[:selected] == '1'
    options_for_select({t('common.yes') => 'true',t('common.no') => 'false'}, owner)
  end

  def bank_account_type_key_for_select(type)
    case type
      when '1'
        'saving_account'
      when '2'
        'checking_account'
      when '3'
        'other'
      else
        ''
    end
  end

  private

  def create_array_for_select(array, translate_key)
    array.map { |option| [t(translate_key + option.to_s), option] }.sort_by { |text, _val| text }
  end


end
