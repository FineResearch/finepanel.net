# frozen_string_literal: true

class TextParser
  DEFAULT_POR_MESSAGE = 'Vc tem uma nova pesquisa dsiponivel'
  DEFAULT_ESP_MESSAGE = 'Tiene una nueva encuesta disponible'

  def initialize(text)
    @text = text
  end

  def get_language_texts
    {
      es: get_spanish_text,
      por: get_portuguese_text
    }
  end

  def match_users_language_file
    @text.match(/Expression Filter: IN\(dynamed, \"1\"\)/)
  end

  private

  def get_portuguese_text
    matches_por = @text.match(/POR=\s?(.*)/)
    matches_por ? matches_por[1] : DEFAULT_POR_MESSAGE
  end

  def get_spanish_text
    matches_esp = @text.match(/ESP=\s?(.*)/)
    matches_esp ? matches_esp[1] : DEFAULT_ESP_MESSAGE
  end
end
