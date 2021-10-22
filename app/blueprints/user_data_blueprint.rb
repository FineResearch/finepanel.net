class UserDataBlueprint < Blueprinter::Base

  field :email do |data|
    data[:email]
  end

  field :country do |data|
    data[:country]
  end

  field :city do |data|
    data[:city]
  end

  field :complete_name do |data|
    "#{data[:first_name]} #{data[:last_name]}"
  end

  field :specialty do |data|
    data[:specialty_id]
  end
end
