# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# PSPP lee mal las columnas de un DATA LIST FIXED que pasan de la 65535 (les da la vuelta modulo 65536):
# la variable se llena con el contenido de otra columna. Es lo que provoco los data_mismatch de
# p215401338743, p899583054321 y p330455179161 (exports con muchos campos "_OTHER" de 4000 caracteres).
# SpssRecordSplitter parte cada linea en varios registros para que ninguna columna pase del limite.
#
# toy_wide.sps/.dat: 22 textos de 4000 bytes (88004 columnas), 3 casos. toy_wide_pspp_bug.sav es lo que
# PSPP 1.6.2 produce compilandolo tal cual (V18 a V22 vacias); toy_wide_split.sav, lo que produce con el
# DATA LIST partido por este servicio (y /KEEP para conservar el orden).
RSpec.describe ExportRelabeling::SpssRecordSplitter do
  let(:fixtures) { Rails.root.join('spec/fixtures/sav') }
  let(:sps) { File.read(fixtures.join('toy_wide.sps'), encoding: 'utf-8') }
  let(:dat) { fixtures.join('toy_wide.dat').to_s }

  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  def copy_of_data
    path = File.join(@dir, 'data.asc')
    FileUtils.cp(dat, path)
    path
  end

  describe '.call' do
    it 'parte el DATA LIST en registros que no pasan del limite y reubica las columnas desde 1' do
      result = described_class.call(sps_text: sps, data_path: copy_of_data)

      expect(result.split?).to be(true)
      expect(result.sps_text).to include('RECORDS=2', "\n/1", "\n/2")
      expect(result.sps_text).to include(' ID 1-4', ' V01 5-4004')
      columns = ExportRelabeling::SpssDataListReader.columns(result.sps_text)
      expect(columns.map { |column| column[:end] }.max).to be <= described_class::MAX_RECORD_BYTES
      expect(columns.map { |column| column[:name] }).to match_array(['ID'] + (1..22).map { |i| format('V%02d', i) })
    end

    it 'ajusta el LRECL al registro mas ancho' do
      result = described_class.call(sps_text: sps, data_path: copy_of_data)

      expect(result.sps_text[%r{/LRECL=(\d+)}, 1].to_i).to be <= described_class::MAX_RECORD_BYTES
    end

    it 'el archivo de datos queda con una linea por registro, sin perder ni repetir ningun byte' do
      result = described_class.call(sps_text: sps, data_path: copy_of_data)

      original = File.binread(dat).split("\n")
      records = File.binread(result.data_path).split("\n")
      expect(records.length).to eq(original.length * 2)
      expect(records.each_slice(2).map(&:join)).to eq(original)
      expect(File.binread(dat)).not_to eq(File.binread(result.data_path))
    end

    it 'no toca el archivo de datos original' do
      path = copy_of_data
      before = File.binread(path)

      described_class.call(sps_text: sps, data_path: path)

      expect(File.binread(path)).to eq(before)
    end

    it 'el /KEEP conserva el orden original del DATA LIST (el del cuestionario)' do
      result = described_class.call(sps_text: sps, data_path: copy_of_data)

      kept = result.keep_clause.sub(%r{\A\s*/KEEP=}, '').split
      expect(kept).to eq(['ID'] + (1..22).map { |i| format('V%02d', i) })
    end

    it 'respeta el orden de un DATA LIST ya reordenado: el /KEEP lleva ese orden, aunque los registros agrupen' do
      lines = sps.lines
      first = lines.index { |line| line.strip == 'V01 5-4004 (A)' || line.strip.start_with?('V01 ') }
      last = lines.index { |line| line.strip.start_with?('V22 ') }
      lines[first], lines[last] = lines[last], lines[first]

      result = described_class.call(sps_text: lines.join, data_path: copy_of_data)

      kept = result.keep_clause.sub(%r{\A\s*/KEEP=}, '').split
      expect(kept.first(2)).to eq(%w[ID V22])
      expect(kept.last).to eq('V01')
    end

    it 'completa con espacios las lineas mas cortas (Confirmit recorta los espacios finales)' do
      short = File.join(@dir, 'short.asc')
      File.binwrite(short, "   1hola\n")
      text = "FILE HANDLE F1\n /NAME = 'x'\n /LRECL=80000.\nDATA LIST\n FIXED FILE = F1\n RECORDS=1\n/1\n ID 1-4\n A 5-60000 (A)\n B 60001-70000 (A)\n.\n"

      result = described_class.call(sps_text: text, data_path: short)

      expect(result.split?).to be(true)
      records = File.binread(result.data_path).split("\n", -1)
      expect(records.first.bytesize).to eq(60_000)
      expect(records[1].bytesize).to eq(10_000)
      expect(records.first).to start_with('   1hola')
    end

    it 'no toca nada si ninguna columna pasa del limite (los exports que ya funcionan quedan igual)' do
      text = "FILE HANDLE F1\n /NAME = 'x'\n /LRECL=100.\nDATA LIST\n FIXED FILE = F1\n RECORDS=1\n/1\n ID 1-4\n A 5-60 (A)\n.\n"
      path = copy_of_data

      result = described_class.call(sps_text: text, data_path: path)

      expect(result.split?).to be(false)
      expect(result.sps_text).to eq(text)
      expect(result.data_path).to eq(path)
      expect(result.keep_clause).to eq('')
    end

    it 'si el DATA LIST no tiene la forma esperada (dos registros), lo deja igual' do
      text = sps.sub(/^ V22 .*$/, " V22 1-4000 (A)\n/2")
      result = described_class.call(sps_text: text, data_path: copy_of_data)

      expect(result.split?).to be(false)
      expect(result.sps_text).to eq(text)
    end

    it 'si una variable no cabe en un registro, lo deja igual en lugar de romperlo' do
      text = "FILE HANDLE F1\n /NAME = 'x'\n /LRECL=100.\nDATA LIST\n FIXED FILE = F1\n RECORDS=1\n/1\n ID 1-4\n A 5-70000 (A)\n.\n"

      expect(described_class.call(sps_text: text, data_path: copy_of_data).split?).to be(false)
    end

    it 'si falla algo al partir (ej. archivo de datos inexistente), deja todo como estaba y no levanta' do
      result = described_class.call(sps_text: sps, data_path: File.join(@dir, 'no_existe.asc'))

      expect(result.split?).to be(false)
      expect(result.sps_text).to eq(sps)
    end
  end

  # Los .sav de abajo los compilo PSPP real: documentan el bug y que el DATA LIST partido lo evita.
  describe 'contra .sav reales de PSPP' do
    it 'sin partir, PSPP deja vacias las variables que pasan de la columna 65535 y el verificador lo detecta' do
      expect do
        ExportRelabeling::SavVerifier.call(sav_path: fixtures.join('toy_wide_pspp_bug.sav').to_s, sps_text: sps, data_path: dat)
      end.to raise_error(ExportRelabeling::SavVerifier::MismatchError)
    end

    it 'con el DATA LIST partido, el .sav coincide celda por celda con el .dat original' do
      summary = ExportRelabeling::SavVerifier.call(sav_path: fixtures.join('toy_wide_split.sav').to_s, sps_text: sps, data_path: dat)

      expect(summary).to include(cases: 3, mismatched_cells: 0)
    end

    it 'y el .sav partido conserva el orden de las variables del DATA LIST' do
      names = ExportRelabeling::SavReader.new(fixtures.join('toy_wide_split.sav').to_s).dictionary.variables.map(&:name)

      expect(names).to eq(['ID'] + (1..22).map { |i| format('V%02d', i) })
    end
  end
end
