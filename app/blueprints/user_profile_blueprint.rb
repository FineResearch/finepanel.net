class UserProfileBlueprint < Blueprinter::Base
  fields :suffix, :first_name, :last_name, :email, :alternate_email, :phone, :country_id, :work_at_id, :crm, :alternate_specialty_id, :city_id, :country_text, :city_text, :origen, :estado, :modo, :specialty_text, :B1, :B2, :B3, :B4, :B5, :B6, :dynamed, :premier

  field :complete_name do |profile|
    "#{profile[:suffix]} #{profile[:last_name]}"
  end

  field :country do |profile|
    ConfigurationReader.country_name(profile[:country_id]) || profile[:country_text]
  end

  field :city do |profile|
    ConfigurationReader.city_name(profile[:country_id], profile[:city_id]) || profile[:city_text]
  end

  field :specialty do |profile|
    profile[:specialty_id]
  end

  field :suffix do |profile|
    profile[:suffix].try(:delete, '.')
  end
end
