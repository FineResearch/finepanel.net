# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ColumnStatistics do
  it 'calcula media, min y max sobre una columna numerica' do
    result = described_class.call([1, 2, 3, 4])

    expect(result[:mean]).to eq(2.5)
    expect(result[:min]).to eq(1)
    expect(result[:max]).to eq(4)
  end

  it 'cuenta nulos (nil y strings vacios/con espacios) sin romper el calculo numerico' do
    result = described_class.call([1, nil, '', '  ', 3])

    expect(result[:null_count]).to eq(3)
    expect(result[:mean]).to eq(2.0)
  end

  it 'calcula el porcentaje de nulos sobre el total de filas, no solo sobre las numericas' do
    result = described_class.call([1, nil, nil, nil])

    expect(result[:null_percentage]).to eq(75.0)
  end

  it 'cuenta los ceros por separado del resto de los valores numericos' do
    result = described_class.call([0, 0, 1, 2])

    expect(result[:zero_count]).to eq(2)
  end

  it 'no trata texto libre como numerico (no rompe ni lo cuenta como valor numerico)' do
    result = described_class.call(['Sim', 'Não', 'Outra especialidade'])

    expect(result[:mean]).to be_nil
    expect(result[:min]).to be_nil
    expect(result[:max]).to be_nil
    expect(result[:null_count]).to eq(0)
  end

  it 'entiende strings numericos (tal como vienen de una celda de Excel leida como texto)' do
    result = described_class.call(['1', '2', '3'])

    expect(result[:mean]).to eq(2.0)
  end

  it 'no rompe con una columna vacia' do
    result = described_class.call([])

    expect(result).to eq(mean: nil, min: nil, max: nil, null_count: 0, zero_count: 0, null_percentage: nil)
  end
end
