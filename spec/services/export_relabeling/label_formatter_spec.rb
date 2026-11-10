# frozen_string_literal: true

require 'rails_helper'

# Los ejemplos salen del modelo que mando el cliente
# (Modelo_Base_Dados_Fine_20261109.xlsx, hoja DB).
RSpec.describe ExportRelabeling::LabelFormatter do
  def format(variable_name, parsed)
    described_class.call(variable_name: variable_name, parsed: parsed)
  end

  it 'arma "VARIABLE : TITULO. pregunta" para una pregunta simple' do
    parsed = { code: 'F0', attribute: nil, question: 'Em qual estado você mora?' }

    expect(format('F0', parsed)).to eq('F0 : F0. Em qual estado você mora?')
  end

  it 'pone el atributo antes de la pregunta en una multiple' do
    parsed = {
      code: 'I3', attribute: 'Cansaço extremo ou esgotamento',
      question: 'Após o término da crise de enxaqueca, quais sintomas você costuma apresentar?'
    }

    expect(format('I3_1', parsed)).to eq(
      'I3_1 : Cansaço extremo ou esgotamento | I3. Após o término da crise de enxaqueca, quais sintomas você costuma apresentar?'
    )
  end

  it 'respeta un atributo de dos niveles (Grid3D: grupo | fila)' do
    parsed = {
      code: 'D1a', attribute: 'SINAIS E SINTOMAS QUE MOTIVARAM A BUSCA DE ESPECIALISTA | Dor de cabeça intensa',
      question: 'Quais os principais sinais e sintomas?'
    }

    expect(format('D1_A_1', parsed)).to eq(
      'D1_A_1 : SINAIS E SINTOMAS QUE MOTIVARAM A BUSCA DE ESPECIALISTA | Dor de cabeça intensa | D1a. Quais os principais sinais e sintomas?'
    )
  end

  it 'deja solo el nombre en una variable de sistema sin texto' do
    expect(format('responseid', { code: nil, attribute: nil, question: nil })).to eq('responseid')
  end

  it 'deja solo el nombre si el texto resuelto es el propio nombre' do
    expect(format('responseid', { code: nil, attribute: nil, question: 'responseid' })).to eq('responseid')
  end

  it 'usa solo la pregunta si no hay titulo' do
    expect(format('status', { code: nil, attribute: nil, question: 'Interview status' })).to eq('status : Interview status')
  end

  it 'usa solo el titulo si no hay texto de pregunta' do
    expect(format('q9_1', { code: 'Q9', attribute: nil, question: nil })).to eq('q9_1 : Q9')
  end

  it 'deja solo el nombre si el titulo es igual a la variable y no hay mas texto' do
    expect(format('q9', { code: 'Q9', attribute: nil, question: nil })).to eq('q9')
  end

  it 'no duplica el punto si el titulo ya lo trae' do
    expect(format('f0', { code: 'F0.', attribute: nil, question: 'Estado?' })).to eq('f0 : F0. Estado?')
  end

  it 'no duplica el titulo si la pregunta ya empieza con el' do
    expect(format('f0', { code: 'F0', attribute: nil, question: 'F0. Estado?' })).to eq('f0 : F0. Estado?')
  end

  it 'colapsa saltos de linea y espacios repetidos (el encabezado es una sola fila)' do
    parsed = { code: 'I2', attribute: nil, question: "Em média, quanto tempo dura?\nSe menos de 1 hora,   inserir 1." }

    expect(format('I2', parsed)).to eq('I2 : I2. Em média, quanto tempo dura? Se menos de 1 hora, inserir 1.')
  end

  it 'descarta el piping de loop pegado al codigo' do
    parsed = { code: "Q0A // ^f('hidden_ficha_nom')^", attribute: nil, question: 'Nome da ficha' }

    expect(format('q0a', parsed)).to eq('q0a : Q0A. Nome da ficha')
  end
end
