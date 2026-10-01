# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::CompletedQuotas do
  HEADER = ExportRelabeling::QuotaProgressBuilder::HEADER.freeze

  it 'devuelve solo las filas donde lo conseguido ya alcanzo o supero la meta (pending <= 0)' do
    rows = [
      HEADER,
      ['quota1', 's0', '1', 50, 51, -1], # completa (supero la meta)
      [nil, nil, '2', 30, 10, 20] # misma cuota/variable (dedupe) -- no completa
    ]

    result = described_class.call(rows)

    expect(result).to eq([{ quota: 'quota1', field: 's0', value: '1', target: 50, achieved: 51 }])
  end

  it 'arrastra el Quota/Variable de la primera linea del grupo cuando vienen en blanco (dedupe)' do
    rows = [
      HEADER,
      ['quota2', 'regiao', 'Sudeste', 50, 20, 30],
      [nil, nil, 'Sudeste', 50, 50, 0] # dedupe -- misma cuota/variable, esta si completa
    ]

    result = described_class.call(rows)

    expect(result).to eq([{ quota: 'quota2', field: 'regiao', value: 'Sudeste', target: 50, achieved: 50 }])
  end

  it 'ignora filas de encabezado repetidas y filas en blanco separadoras entre bloques' do
    rows = [
      HEADER,
      ['quota1', 's0', '1', 10, 10, 0],
      Array.new(HEADER.length), # fila en blanco entre bloques
      HEADER,
      ['quota2', 's1', '2', 5, 5, 0]
    ]

    result = described_class.call(rows)

    expect(result).to eq([
      { quota: 'quota1', field: 's0', value: '1', target: 10, achieved: 10 },
      { quota: 'quota2', field: 's1', value: '2', target: 5, achieved: 5 }
    ])
  end

  it 'ignora filas donde "achieved" es un string (variable not found / cruce no soportado), no un numero' do
    rows = [
      HEADER,
      ['quota1', 's0', '1', 10, ExportRelabeling::QuotaProgressBuilder::NOT_FOUND, nil]
    ]

    expect(described_class.call(rows)).to eq([])
  end

  it 'devuelve vacio si no hay filas' do
    expect(described_class.call(nil)).to eq([])
    expect(described_class.call([])).to eq([])
  end
end
