# frozen_string_literal: true

require 'csv'

module FilesHelper
  def tab_separated_to_hash(file_path)
    csv = ''

    File.open(file_path) do |file|
      file.each_line do |line|
        csv += line.tr!("\t", ',')
      end
    end

    CSV.parse(csv, headers: true, header_converters: :symbol, skip_blanks: true)
  end
end
