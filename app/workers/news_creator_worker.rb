class NewsCreatorWorker
  include Sidekiq::Worker

  def perform(dynamed_id)
    DynamedApi::CreateNews.new(dynamed_id).process

    logger.info("Finished NewsCreatorWorker => dynamed_id: #{dynamed_id}")
  end
end
