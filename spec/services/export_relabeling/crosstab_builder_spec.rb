# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::CrosstabBuilder do
  let(:header_class) { ExportRelabeling::ExcelReader::Header }

  let(:main_source) do
    {
      headers: [header_class.new('status', 'status'), header_class.new('quotareg', 'quotareg'), header_class.new('s0', 's0')],
      rows: [
        %w[complete Sudeste 1],
        %w[complete Sudeste 1],
        %w[complete Sul 2],
        %w[screened Sudeste 1] # no cuenta -- no esta completo
      ],
      status_variable: 'status',
      complete_value: 'complete'
    }
  end

  let(:fichas_source) do
    {
      headers: [header_class.new('fichaestado', 'fichaestado'), header_class.new('tipoficha', 'tipoficha')],
      rows: [%w[completa A], %w[completa A], %w[incompleta B]],
      status_variable: 'fichaestado',
      complete_value: 'completa'
    }
  end

  let(:sources) { [main_source, fichas_source] }

  # El titulo ("variable_a x variable_b") se resalta en negrita + fondo
  # amarillo (ver ExcelWriter) -- header_indices apunta a esas filas. La
  # vieja fila "variable_a \ variable_b" ya no se escribe (era redundante
  # con el titulo) -- la esquina de la tabla de valores queda en blanco.
  it 'arma un crosstab con conteos, filtrando por completitud, con totales por fila y por columna' do
    result = described_class.call(crosses: [{ variable_a: 'quotareg', variable_b: 's0' }], sources: sources)

    expect(result[:rows]).to eq(
      [
        ['quotareg x s0'],
        [nil, '1', '2', 'Total'],
        ['Sudeste', 2, 0, 2],
        ['Sul', 0, 1, 1],
        ['Total', 2, 1, 3]
      ]
    )
    expect(result[:header_indices]).to eq([0])
  end

  it 'funciona igual para 2 variables que viven en el loop' do
    result = described_class.call(crosses: [{ variable_a: 'fichaestado', variable_b: 'tipoficha' }], sources: sources)

    # fichaestado es la propia variable de completitud del loop -- solo
    # queda el valor "completa" (el "incompleta" ya se filtro).
    expect(result[:rows]).to eq(
      [
        ['fichaestado x tipoficha'],
        [nil, 'A', 'Total'],
        ['completa', 2, 2],
        ['Total', 2, 2]
      ]
    )
  end

  it 'marca "no encontrada" si alguna variable no existe en ningun archivo' do
    result = described_class.call(crosses: [{ variable_a: 'no_existe', variable_b: 's0' }], sources: sources)

    expect(result[:rows]).to eq([['no_existe x s0'], [described_class::NOT_FOUND]])
    expect(result[:header_indices]).to eq([0])
  end

  it 'marca "no se puede cruzar" si las 2 variables viven en archivos distintos' do
    result = described_class.call(crosses: [{ variable_a: 's0', variable_b: 'tipoficha' }], sources: sources)

    expect(result[:rows]).to eq([['s0 x tipoficha'], [described_class::CROSS_SOURCE_UNSUPPORTED]])
  end

  it 'separa cada crosstab con una fila en blanco cuando hay varios, y apunta el titulo de cada uno en header_indices' do
    result = described_class.call(
      crosses: [{ variable_a: 'quotareg', variable_b: 's0' }, { variable_a: 'no_existe', variable_b: 's0' }],
      sources: sources
    )

    blank_index = result[:rows].index([])
    expect(blank_index).not_to be_nil
    expect(result[:rows][blank_index + 1]).to eq(['no_existe x s0'])
    expect(result[:header_indices]).to eq([0, blank_index + 1])
  end
end
