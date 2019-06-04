# frozen_string_literal: true

require 'configuration_reader'

module RegistrationsHelper
  def options_for_country_select(_resource = nil, country_id = nil)
    countries = ConfigurationReader.countries.map { |country| [t(country[0]), country[1]] }
    options_for_select(countries.sort, country_id)
  end

  def options_for_city_select(country_id = 1)
    cities = ConfigurationReader.cities(country_id).map { |city| [t(city[0]), city[1]] }.sort
    if cities.blank?
      options_for_select([])
    else
      options_for_select(cities, nil)
    end
  end

  def options_for_suffix_select(_resource = nil)
    suffixes = ConfigurationReader.suffixes
    options_for_select(create_array_for_select(suffixes, 'suffixes.'))
  end

  def options_for_specialty_select(_resource = nil)
    specialties = ConfigurationReader.specialties
    options_for_select(create_array_for_select(specialties, 'specialties.s'))
  end

  def options_for_work_at_select(_resource = nil)
    work_at_options = ConfigurationReader.work_at_options
    options_for_select(create_array_for_select(work_at_options, 'work_at_options.w'))
  end

  private

  def create_array_for_select(array, translate_key)
    array.map { |option| [t(translate_key + option.to_s), option] }.sort_by { |text, _val| text }
  end
end
