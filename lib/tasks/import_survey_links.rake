# frozen_string_literal: true

require 'csv'

task :import_survey_links, %i[file_path project_id] => :environment do |_t, args|
  path_regex = args[:file_path] + args[:project_id] + '_*.txt'
  path = Dir[path_regex]
  CSV.foreach(path.first, encoding: 'UTF-8', col_sep: "\t", headers: true) do |row|
    spanel = row[1].split('=').last
    survey = SurveyLink.find_or_create_by(project_id: args[:project_id], resp_id: row[0], link: row[1], spanel: spanel, variables: row[2])
    puts survey.errors.first[1] unless survey.valid?
  end
end
