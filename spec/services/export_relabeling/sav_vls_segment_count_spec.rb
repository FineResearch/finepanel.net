# frozen_string_literal: true

require 'rails_helper'

# Una cadena muy larga de ancho W se guarda en ceil(W / 252) segmentos (no ceil(W / 255)), aunque cada
# segmento lleve hasta 255 bytes de texto. Con W = 510, 765, 1020, 2040 o 4080 sobra un ultimo segmento que
# no trae texto: si el lector no lo consume queda como una variable de mas y corre las columnas siguientes.
# Ese fue el falso data_mismatch de p330455179161 (campos *_OTHER): el .sav estaba bien.
#
# toy_widths.sav lo compilo PSPP 1.6.2 desde toy_widths.sps y toy_widths.dat: 14 textos de ancho 256 a 4080,
# cada uno seguido de un numerico de 3 columnas que delata cualquier corrimiento. La fila 2 va vacia y las
# otras llenan todo el ancho. Se contrasto ademas con pyreadstat: 0 diferencias.
RSpec.describe 'cuenta de segmentos de las cadenas muy largas' do
  let(:fixtures) { Rails.root.join('spec/fixtures/sav') }
  let(:sav) { fixtures.join('toy_widths.sav').to_s }
  let(:sps) { File.read(fixtures.join('toy_widths.sps'), encoding: 'utf-8') }
  let(:dat) { fixtures.join('toy_widths.dat').to_s }
  let(:widths) { [256, 300, 504, 510, 756, 765, 1000, 1008, 1020, 2000, 2040, 4000, 4032, 4080] }

  it 'el lector ve exactamente las variables del DATA LIST, tambien con anchos donde ceil(W/252) != ceil(W/255)' do
    names = ExportRelabeling::SavReader.new(sav).dictionary.variables.map(&:name)

    expect(names).to eq(['ID'] + widths.flat_map { |width| ["T#{width}", "N#{width}"] })
  end

  it 'los numericos que siguen a cada texto largo no se corren' do
    rows = []
    ExportRelabeling::SavReader.new(sav).each_case { |_index, values| rows << values }

    rows.each_with_index do |values, row|
      numbers = values.drop(1).each_slice(2).map(&:last)
      # el generador asigna a cada variable (texto o numerica) un k correlativo: la numerica de cada par es k impar
      expected = widths.each_index.map { |pair| (((pair * 2) + 1) * 11 + row) % 999 }.map(&:to_f)
      expect(numbers).to eq(expected)
    end
  end

  it 'el verificador aprueba el .sav completo (0 celdas distintas)' do
    summary = ExportRelabeling::SavVerifier.call(sav_path: sav, sps_text: sps, data_path: dat)

    expect(summary).to include(cases: 3, mismatched_cells: 0)
  end
end
