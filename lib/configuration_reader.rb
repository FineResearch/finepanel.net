# frozen_string_literal: true

module ConfigurationReader
  ENUM_FILE_NAME = 'enums.yml'
  COUNTRY_FILE_NAME = 'countries.yml'
  CONSTANTS_FILE_NAME = 'constants.yml'

  def self.suffixes
    load_config('suffixes', ENUM_FILE_NAME)
  end

  def self.specialties
    load_config('specialties', ENUM_FILE_NAME)
  end

  def self.work_at_options
    load_config('work_at_options', ENUM_FILE_NAME)
  end

  def self.countries
    countries = load_config('countries', COUNTRY_FILE_NAME)
    countries.keys.map { |country_key| ["countries.co#{countries[country_key]['id']}", countries[country_key]['id']] }
  end

  def self.cities(country_id)
    countries = load_config('countries', COUNTRY_FILE_NAME)
    begin
      countries["co#{country_id}"]['cities']
        .keys.map { |city_key| ["countries.cities.co#{country_id}.ci#{countries["co#{country_id}"]['cities'][city_key]['id']}", countries["co#{country_id}"]['cities'][city_key]['id']] }
    rescue StandardError
      []
    end
  end

  def self.user_profile_path
    load_config('user_profile_path', CONSTANTS_FILE_NAME)
  end

  def self.load_config(enum, file_name)
    YAML.safe_load(File.open(Rails.root.join('config', file_name)))[enum]
  end
end
