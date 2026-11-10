# frozen_string_literal: true

# Arma el label unico de UNA columna con el formato del modelo que pidio el
# cliente (IQVIA, acta del 06/11/2026):
#
#   VARIABLE : atributo | TITULO. pregunta
#
# - Variable de sistema o sin texto: solo el nombre ("responseid").
# - Simple: "F0 : F0. Em qual estado voce mora?"
# - Multiple/Grid: "I3_1 : Cansaco extremo | I3. Apos o termino..."
# - Grid3D (2 niveles): el atributo ya viene como "GRUPO | fila".
#
# El atributo va ANTES de la pregunta a proposito: SPSS corta el label
# alrededor de 250 caracteres, y si el texto largo de la pregunta fuera
# primero se perderia justo lo que identifica a la columna (ver
# SpssSyntaxRewriter, que trunca por el final).
#
# El mismo string se usa en el encabezado del Excel y en el VARIABLE LABELS
# del SPSS ("el label del SPSS vira igual a la primera linea del Excel").
#
# El sufijo de piping de un archivo de loop ("// ^f('...')^", ver
# LabelParser.split_loop_reference) es identico en TODA columna y no ayuda a
# leer el encabezado, asi que se descarta aca; el Dictionary lo conserva.
module ExportRelabeling
  class LabelFormatter
    SEPARATOR = ' | '

    def self.call(variable_name:, parsed:)
      new(variable_name, parsed).call
    end

    def initialize(variable_name, parsed)
      @variable_name = variable_name.to_s.strip
      @parsed = parsed || {}
    end

    def call
      body = [attribute, title_and_question].reject(&:blank?).join(SEPARATOR)
      return @variable_name if body.blank? || body.casecmp?(@variable_name)

      "#{@variable_name} : #{body}"
    end

    private

    def attribute
      squish(@parsed[:attribute])
    end

    def code
      cleaned, = LabelParser.split_loop_reference(@parsed[:code])
      squish(cleaned)
    end

    def question
      squish(@parsed[:question])
    end

    # "F0. Em qual estado..." -- el punto separa el titulo de la pregunta, tal
    # cual lo ve el entrevistado. Si el titulo ya trae su propio punto, o si la
    # pregunta ya empieza con el titulo, no se duplica.
    def title_and_question
      return question if code.blank?
      return code if question.blank?
      return question if question.downcase.start_with?("#{code.downcase.chomp('.')}.")

      "#{code.chomp('.')}. #{question}"
    end

    def squish(text)
      text.to_s.gsub(/\s+/, ' ').strip.presence
    end
  end
end
