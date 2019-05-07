# frozen_string_literal: true

module ConfigurationReader
  ENUM_FILE_NAME = 'enums.yml'
  COUNTRY_FILE_NAME = 'countries.yml'

  def self.suffixes
    load_config('suffixes')
  end

  def self.specialties
    load_config('specialties')
  end

  def self.work_at_options
    load_config('work_at_options')
  end

  def self.countries
    countries = load_config('countries')
    countries.keys.map { |country_key| ["countries.co#{countries[country_key]['id']}", countries[country_key]['id']] }
  end

  def self.cities(country_id)
    countries = load_config('countries')
    begin
      countries["co#{country_id}"]['cities']
        .keys.map { |city_key| ["countries.cities.co#{country_id}.ci#{countries["co#{country_id}"]['cities'][city_key]['id']}", countries["co#{country_id}"]['cities'][city_key]['id']] }
    rescue StandardError
      []
    end
  end

  def load_config(enum)  
    YAML.safe_load(File.open(Rails.root.join('config', ENUM_FILE_NAME)))[enum]
  end
end
