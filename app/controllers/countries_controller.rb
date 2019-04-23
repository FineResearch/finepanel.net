# frozen_string_literal: true

class CountriesController < ApplicationController
  def cities
    response_cities = ConfigurationReader.cities(params[:country_id])
    render json: response_cities.map { |city| [t(city[0]), city[1]] }.sort
  end
end
