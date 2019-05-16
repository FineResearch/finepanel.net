require 'csv'

class SyncSurveyLinks
  class << self
    
    def import_survey_links(file_path)
      project_id = file_path.match(/p\d+/).to_s

      CSV.foreach(file_path, col_sep: "\t", headers: true) do |row|
        spanel = row[1].split('=').last
        survey = SurveyLink.find_or_create_by(project_id: project_id, resp_id: row[0], link: row[1], spanel: spanel, variables: row[2])
        puts survey.errors.first[1] unless survey.valid?
      end
    end

  end
end
