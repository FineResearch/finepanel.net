require 'sidekiq-scheduler'

class ArticlesCreatorWorker
  include Sidekiq::Worker

  def perform(*args)
    return unless args.present?
    elements = args[0]
    position = args[1]

    Specialty.limit(elements).offset(position).each do |specialty|
      next unless specialty.present?
      DynamedApi::CreateArticles.new(specialty).process
    end
  end
end
