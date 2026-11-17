# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# Cadenas de mas de 255 bytes (los campos "otro" de Confirmit, A4000): el .sav las guarda como
# varios segmentos y las reune el registro de info 14. Antes el verificador se saltaba esos proyectos
# ("cadenas de mas de 255 bytes": FP-18928G, FP-18737C), justo los que mas campos abiertos tienen.
#
# toy_long.sav lo compilo PSPP 1.6.2 desde toy_long.sps y toy_long_utf8.dat: BIG_TEXT A4000, MID_TEXT A300
# y EDGE A255 (el limite exacto). El texto usa tokens numericos para que cada posicion sea distinguible.
RSpec.describe 'cadenas de mas de 255 bytes en un .sav' do
  let(:fixtures) { Rails.root.join('spec/fixtures/sav') }
  let(:sav) { fixtures.join('toy_long.sav').to_s }
  let(:sps) { File.read(fixtures.join('toy_long.sps'), encoding: 'utf-8') }
  let(:dat) { fixtures.join('toy_long_utf8.dat').to_s }

  let(:big_row1) { (0...800).map { |i| format('%04d', i) + (i % 7 == 0 ? 'é' : ' ') }.join[0, 3500].rstrip }
  let(:big_row3) { (0...800).map { |i| format('%04d ', i) }.join[0, 4000].rstrip }
  let(:mid_row3) { (0...100).map { |i| format('%02d', i) + (i % 5 == 0 ? 'ñ' : '-') }.join[0, 300] }

  def cases
    rows = []
    ExportRelabeling::SavReader.new(sav).each_case { |_index, values| rows << values }
    rows
  end

  def utf8(value)
    value.dup.force_encoding(Encoding::UTF_8)
  end

  describe ExportRelabeling::SavReader do
    it 'reune los segmentos en UNA variable con su ancho real' do
      reader = described_class.new(sav).dictionary

      expect(reader.variables.map { |variable| [variable.name, variable.width] })
        .to eq([['ID', 0], ['BIG_TEXT', 4000], ['MID_TEXT', 300], ['EDGE', 255], ['NUM', 0]])
    end

    it 'lee el texto de 4000 bytes completo, sin perder ni repetir nada en los limites entre segmentos' do
      rows = cases

      expect(utf8(rows[2][1])).to eq(big_row3)
      expect(utf8(rows[2][1]).length).to eq(big_row3.length)
    end

    it 'lee un texto largo con tildes pasado el limite del primer segmento' do
      expect(utf8(cases[0][1])).to eq(big_row1)
    end

    it 'un texto vacio, uno corto y uno de exactamente 255 caracteres siguen bien; los numeros de despues no se corren' do
      rows = cases

      expect(rows[1]).to eq([2.0, '', 'corto', '', nil])
      expect(utf8(rows[0][3])).to eq('e' * 255)
      expect(rows.map(&:last)).to eq([10.0, nil, 30.0])
    end

    it 'el texto de 300 bytes que PSPP trunca a 300 BYTES (tiene tildes) queda como prefijo del original' do
      stored = utf8(cases[2][2])

      expect(mid_row3).to start_with(stored)
      expect(stored.length).to be >= 280
    end
  end

  describe ExportRelabeling::SavVerifier do
    it 'verifica un .sav con textos largos en lugar de saltearlo' do
      summary = described_class.call(sav_path: sav, sps_text: sps, data_path: dat)

      expect(summary).to include(cases: 3, cells: 15, mismatched_cells: 0)
    end

    it 'detecta un desfasaje en un .sav con textos largos' do
      Dir.mktmpdir do |dir|
        shifted = File.join(dir, 'shifted.dat')
        File.write(shifted, File.binread(dat).lines.map { |line| line[1..-1] }.join, mode: 'wb')

        expect { described_class.call(sav_path: sav, sps_text: sps, data_path: shifted) }
          .to raise_error(described_class::MismatchError)
      end
    end
  end
end
