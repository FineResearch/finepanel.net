namespace :newsfeed do
  desc "create FinaPanel Specialties"
  task create_specialties: :environment do
    specialties = [{name: 'Oncología', slug: 'oncology'}, {name: 'Clínica Médica', slug: 'family_medicine'}, {name: 'Hematología', slug: 'hematology'}, {name: 'Cardiología', slug: 'cardiology'}, {name: 'Endocrinólogos', slug: 'endocrinology'}, {name: 'Neurología', slug: 'neurology'}, {name: 'Dermatología', slug: 'dermatology'}, {name: 'Pediatría', slug: 'pediatrics'}, {name: 'Reumatología', slug: 'rheumatology'}, {name: 'Gastroenterología', slug: 'gastroenterology'}, {name: 'Neumonología', slug: 'pulmonary_medicine'}, {name: 'Oftalmología', slug: 'ophthalmology'}, {name: 'Ginecología', slug: 'gynecology'}, {name: 'Obstetricia', slug: 'obstetric_medicine'}, {name: 'Infectología', slug: 'infectious_diseases'}, {name: 'Urología', slug: 'urology'}, {name: 'Psiquiatria', slug: 'psychiatry'} ]

    specialties.each do |specialty|
      Rails.logger.info("Specialty => #{specialty[:name]} created") if Specialty.create!(name: specialty[:name], slug: specialty[:slug])
    end
  end

  desc "create articles by Specialty"
  task create_articles: :environment do
    return Rails.logger.warn('Specialty missing') unless ENV['SPECIALTY'].present?
    DynamedApi::CreateArticles.new(ENV['SPECIALTY']).process
  end
end
