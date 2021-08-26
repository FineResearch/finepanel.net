# frozen_string_literal: true

desc 'Run linters'
task :linters do
  sh 'rubocop'
  sh 'rails_best_practices'
  sh 'reek'
end
