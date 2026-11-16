# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ColumnOrder do
  # lookup falso: la posicion de cada columna sale de un hash (nil = no esta en el schema).
  def lookup_with(positions)
    double('lookup').tap do |lookup|
      allow(lookup).to receive(:column_position) { |name| positions[name.to_s.downcase] }
    end
  end

  def sheet_for(names, date_columns: [])
    headers = names.map { |name| ExportRelabeling::ExcelReader::Header.new(name, name) }
    ExportRelabeling::ExcelReader::Sheet.new('Sheet1', headers, [names.each_index.map { |i| "v#{i}" }], date_columns)
  end

  # p378408306422: s11x1b_2 caia en medio de s11x1a, y s11x3aa dentro de s12.
  let(:positions) do
    {
      's11x1a_1' => [1, 0, 0], 's11x1a_2' => [1, 1, 0], 's11x1a_3' => [1, 2, 0], 's11x1a_4' => [1, 3, 0],
      's11x1b_1' => [2, 0, 0], 's11x1b_2' => [2, 1, 0], 's12_1' => [3, 0, 0], 's12_2' => [3, 1, 0], 's11x3aa' => [4, 0, 0]
    }
  end

  describe '.call' do
    it 'deja las columnas en el orden del cuestionario' do
      names = %w[s11x1a_1 s11x1a_2 s11x1a_3 s11x1b_2 s11x1a_4 s11x1b_1 s12_1 s11x3aa s12_2]

      sheet = described_class.call(sheet_for(names), lookup_with(positions))

      expect(sheet.headers.map(&:variable_name)).to eq(%w[s11x1a_1 s11x1a_2 s11x1a_3 s11x1a_4 s11x1b_1 s11x1b_2 s12_1 s12_2 s11x3aa])
    end

    it 'mueve los datos junto con su columna' do
      names = %w[s11x1b_2 s11x1a_1]
      source = sheet_for(names)
      source.rows = [%w[dato_b2 dato_a1]]

      sheet = described_class.call(source, lookup_with(positions))

      expect(sheet.headers.map(&:variable_name)).to eq(%w[s11x1a_1 s11x1b_2])
      expect(sheet.rows).to eq([%w[dato_a1 dato_b2]])
    end

    it 'las columnas que el schema no conoce se quedan donde estaban' do
      names = %w[responseid s11x1b_1 status s11x1a_1 respid]

      sheet = described_class.call(sheet_for(names), lookup_with(positions))

      expect(sheet.headers.map(&:variable_name)).to eq(%w[responseid s11x1a_1 status s11x1b_1 respid])
    end

    it 'las columnas de fecha siguen a su columna' do
      names = %w[s11x1b_1 s11x1a_1 s12_1]

      sheet = described_class.call(sheet_for(names, date_columns: [0]), lookup_with(positions))

      expect(sheet.headers.map(&:variable_name)).to eq(%w[s11x1a_1 s11x1b_1 s12_1])
      expect(sheet.date_columns).to eq([1])
    end

    it 'si ya esta en orden devuelve la misma planilla' do
      source = sheet_for(%w[s11x1a_1 s11x1a_2 s12_1])

      expect(described_class.call(source, lookup_with(positions))).to equal(source)
    end

    it 'sin lookup (no se pudo traer el schema) deja todo como llego' do
      source = sheet_for(%w[s12_1 s11x1a_1])

      expect(described_class.call(source, nil)).to equal(source)
    end

    it 'si el lookup falla, deja el orden original en vez de romper el export' do
      lookup = double('lookup')
      allow(lookup).to receive(:column_position).and_raise(StandardError, 'schema roto')
      source = sheet_for(%w[s12_1 s11x1a_1])

      expect(described_class.call(source, lookup)).to equal(source)
    end
  end

  describe '.permutation' do
    it 'devuelve nil si hay menos de 2 columnas conocidas' do
      expect(described_class.permutation(%w[responseid s12_1], lookup_with(positions))).to be_nil
    end
  end
end
