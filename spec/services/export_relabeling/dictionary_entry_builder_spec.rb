# frozen_string_literal: true

require 'rails_helper'

# Las filas salen del modelo del cliente (Modelo_Base_Dados_Fine_20261109.xlsx,
# hoja Dictionary): Variable | Code | Attribute | Question | Mean | Min | Max |
# Nulls | % Nulls | Zeros | Type | Answer Options.
RSpec.describe ExportRelabeling::DictionaryEntryBuilder do
  def build(variable_name:, values:, parsed: { code: nil, attribute: nil, question: nil }, profile: nil)
    described_class.call(variable_name: variable_name, parsed: parsed, values: values, profile: profile)
  end

  describe 'con el tipo resuelto por el schema' do
    it 'Single: lista las opciones "precode = texto" y no calcula media/min/max' do
      row = build(
        variable_name: 'F0', values: %w[1 2 1],
        parsed: { code: 'F0', attribute: nil, question: 'Em qual estado você mora?' },
        profile: { type: :single, options: [['1', 'Rio de Janeiro'], ['2', 'São Paulo']] }
      )

      expect(row).to eq(['F0', 'F0', '-', 'Em qual estado você mora?', '-', '-', '-', 0, 0.0, 0, 'Single',
                         '1 = Rio de Janeiro | 2 = São Paulo'])
    end

    it 'Multi: 0/1, con el atributo y el codigo de la pregunta' do
      row = build(
        variable_name: 'I3_1', values: %w[1 1 0 1],
        parsed: { code: 'I3', attribute: 'Cansaço extremo', question: 'Sintomas?' },
        profile: { type: :multi }
      )

      expect(row[1..3]).to eq(['I3', 'Cansaço extremo', 'Sintomas?'])
      expect(row[4..6]).to eq(%w[- - -])
      expect(row[9]).to eq(1)
      expect(row[10..11]).to eq(['Multi', '0 = Not selected | 1 = Selected'])
    end

    it 'Numeric: media, min y max' do
      row = build(variable_name: 'I2', values: %w[48 3 12 18], profile: { type: :numeric })

      expect(row[4..6]).to eq([20.25, 3.0, 48.0])
      expect(row[10..11]).to eq(['Numeric', '-'])
    end

    it 'Text vinculado a una opcion "otros": ceros no aplica y se explica a que opcion pertenece' do
      row = build(variable_name: 'I3_99_OTHER', values: ['', '', 'Tontura', ''],
                  profile: { type: :other_text, linked_to: 'I3_99' })

      expect(row[7]).to eq(3)
      expect(row[8]).to eq(75.0)
      expect(row[9]).to eq('-')
      expect(row[10..11]).to eq(['Text', 'Open text linked to I3_99'])
    end

    it 'escala: "N-point scale" con la etiqueta de cada punto' do
      row = build(
        variable_name: 'P1_1', values: %w[3 4 5],
        profile: { type: :scale, scale_points: 5, options: [%w[1 1], %w[2 2], %w[3 3], %w[4 4], %w[5 5]] }
      )

      expect(row[4..6]).to eq(%w[- - -])
      expect(row[10..11]).to eq(['5-point scale', '1 = 1 | 2 = 2 | 3 = 3 | 4 = 4 | 5 = 5'])
    end

    it 'escala sin etiquetas por punto: se explica por sus numeros' do
      row = build(variable_name: 'P1_1', values: %w[1 2], profile: { type: :scale, scale_points: 3, options: [] })

      expect(row[11]).to eq('1 = 1 | 2 = 2 | 3 = 3')
    end

    it 'escala cuyos puntos no se pudieron resolver: "Scale" a secas, no "0-point scale"' do
      row = build(variable_name: 'P1_1', values: %w[1 2], profile: { type: :scale, scale_points: 0, options: [] })

      expect(row[10..11]).to eq(%w[Scale -])
    end

    it 'fecha' do
      row = build(variable_name: 'data', values: ['2026-11-01'], profile: { type: :date })

      expect(row[9]).to eq('-')
      expect(row[10..11]).to eq(%w[Date -])
    end
  end

  describe 'sin schema (variable de sistema o lookup no disponible)' do
    it 'deduce Numeric de los datos' do
      row = build(variable_name: 'responseid', values: %w[1 2 3])

      expect(row[10..11]).to eq(['Numeric', '-'])
      expect(row[4]).to eq(2.0)
    end

    it 'deduce Text si hay algun valor no numerico' do
      row = build(variable_name: 'status', values: %w[complete screened])

      expect(row[9]).to eq('-')
      expect(row[10..11]).to eq(['Text', '-'])
    end

    it 'una columna sin valores no inventa un tipo' do
      row = build(variable_name: 'vacia', values: ['', nil])

      expect(row[10..11]).to eq(%w[- -])
      expect(row[7]).to eq(2)
    end
  end

  it 'muestra "-" en code, attribute y question cuando no hay texto (no una celda vacia)' do
    row = build(variable_name: 'x', values: %w[1], parsed: { code: nil, attribute: '', question: nil })

    expect(row[1..3]).to eq(%w[- - -])
  end

  it 'Zeros no aplica si la columna mezcla valores no numericos' do
    row = build(variable_name: 'q', values: %w[0 abc], profile: { type: :single, options: [] })

    expect(row[9]).to eq('-')
    expect(row[11]).to eq('-')
  end
end
