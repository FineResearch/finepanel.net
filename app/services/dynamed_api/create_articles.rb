module DynamedApi
  class CreateArticles

    CATEGORY_PATH = '/medsapi-dynamed/v1/categories/'

    def initialize(specialty)
      @specialty    = specialty
      @specialty_id = Specialty.find_by_slug(specialty).try(:id)
    end

    def process
      return set_error unless @specialty_id.present?
      data = DynamedApi::Client.new("#{CATEGORY_PATH}#{@specialty}").process

      extract_articles(data['children']) if data['children']
    end

    private

    def set_error
      Rails.logger.warn("===> Specialty #{@specialty} doesn't  exist")
    end

    def extract_articles(data)
      data.each do |z1|
        if z1['resources'].present?
          z1['resources'].each do |z2|
            create_article(z2)
          end
        else
          z1['children'].each do |z3|
            if z3['resources'].present?
              z3['resources'].each do |z4|
                create_article(z4)
              end
            else
              z3['children'].each do |z5|
                if z5['resources'].present?
                  z5['resources'].each do |z6|
                    create_article(z6)
                  end
                end
              end
            end
          end
        end
      end
    end

    def create_article(article_data)
      article = Article.new(dynamed_id: article_data['id'], title: article_data['title'], slug: article_data['slug'], specialty_id: @specialty_id)

      if article.save
        Rails.logger.info("Article #{article.dynamed_id} created")
      else
        Rails.logger.warn("#{article.errors.messages} ----- #{article_data}")
      end
    end

  end
end
