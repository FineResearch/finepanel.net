# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# Fixtures (spec/fixtures/sav): toy.sav lo compilo PSPP 1.6.2 a partir de toy.sps y el .dat
# (toy_utf8.dat es el original en UTF-8; PSPP lo leyo ya convertido a Windows-1252). Tiene
# numeros, perdidos, tildes, un texto que PSPP trunca (A200 con una "é" de mas) y una
# variable de nombre largo (NOTE_TEXT_LONG), con value labels.
RSpec.describe ExportRelabeling::SavReader do
  let(:sav) { Rails.root.join('spec/fixtures/sav/toy.sav').to_s }

  def cases
    rows = []
    described_class.new(sav).each_case { |_i, values| rows << values }
    rows
  end

  it 'lee las variables con su nombre largo y su ancho' do
    reader = described_class.new(sav).dictionary

    expect(reader.variables.map(&:name)).to eq(%w[ID NAME SCORE FLAG NOTE_TEXT_LONG DEC])
    expect(reader.variables.map(&:width)).to eq([0, 20, 0, 0, 200, 0])
  end

  it 'lee los casos: numeros, perdidos (nil) y cadenas con tildes' do
    rows = cases

    expect(rows.length).to eq(4)
    expect(rows[0]).to eq([1.0, 'José Núñez'.b, 85.0, 1.0, 'Hérnia de disco'.b, 1.5])
    expect(rows[1]).to eq([2.0, 'Ana', nil, nil, '', nil])
    expect(rows[2][2..3]).to eq([100.0, 0.0])
    expect(rows[3][1]).to eq('Gül ? €'.b) # la "ğ" no existe en Windows-1252: queda "?"
    expect(rows[3][5]).to eq(2.25)
  end

  it 'un archivo que no es .sav levanta UnsupportedFormat' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'x.sav')
      File.write(path, 'esto no es un sav' * 20)

      expect { described_class.new(path).dictionary }.to raise_error(described_class::UnsupportedFormat)
    end
  end
end

RSpec.describe ExportRelabeling::SavVerifier do
  let(:fixtures) { Rails.root.join('spec/fixtures/sav') }
  let(:sav) { fixtures.join('toy.sav').to_s }
  let(:sps) { File.read(fixtures.join('toy.sps'), encoding: 'utf-8') }
  let(:dat) { fixtures.join('toy_utf8.dat').to_s }

  def verify(data_path: dat, sav_path: sav)
    described_class.call(sav_path: sav_path, sps_text: sps, data_path: data_path)
  end

  it 'un .sav que coincide con su .dat pasa (incluidos tildes, perdidos, decimales y el texto truncado por PSPP)' do
    summary = verify

    expect(summary).to include(cases: 4, rows: 4, cells: 24, mismatched_cells: 0)
  end

  # El caso de FP-18810G: el .sav tenia las columnas corridas respecto del .dat.
  it 'un .dat con las columnas desplazadas respecto del .sav levanta MismatchError con las variables afectadas' do
    Dir.mktmpdir do |dir|
      shifted = File.join(dir, 'shifted.dat')
      # una columna de menos al principio de cada linea: todo queda corrido
      File.write(shifted, File.binread(dat).lines.map { |line| line[1..-1] }.join, mode: 'wb')

      expect { verify(data_path: shifted) }.to raise_error(described_class::MismatchError, /no coinciden con el \.dat.*variable\(s\) afectadas/m)
    end
  end

  it 'el mensaje de un desfasaje nombra la variable, la fila y los valores' do
    Dir.mktmpdir do |dir|
      altered = File.join(dir, 'altered.dat')
      File.write(altered, File.binread(dat).sub('  85', '  12'), mode: 'wb')

      expect { verify(data_path: altered) }.to raise_error(described_class::MismatchError, /SCORE.*fila 1/m)
    end
  end

  it 'un .dat con otra cantidad de casos levanta MismatchError' do
    Dir.mktmpdir do |dir|
      shorter = File.join(dir, 'shorter.dat')
      File.write(shorter, File.binread(dat).lines.first(3).join, mode: 'wb')

      expect { verify(data_path: shorter) }.to raise_error(described_class::MismatchError, /4 casos y el \.dat 3/)
    end
  end

  it 'tolera el BOM UTF-8 al principio del .dat' do
    Dir.mktmpdir do |dir|
      with_bom = File.join(dir, 'bom.dat')
      File.write(with_bom, "\xEF\xBB\xBF".b + File.binread(dat), mode: 'wb')

      expect(verify(data_path: with_bom)).to include(mismatched_cells: 0)
    end
  end

  it 'un .sps sin columnas, o con otra cantidad de variables, no se puede verificar (UnverifiableError, no un fallo del .sav)' do
    expect { described_class.call(sav_path: sav, sps_text: 'nada', data_path: dat) }
      .to raise_error(described_class::UnverifiableError)

    short_sps = sps.sub(" DEC 229-232\n", '')
    expect { described_class.call(sav_path: sav, sps_text: short_sps, data_path: dat) }
      .to raise_error(described_class::UnverifiableError, /6 variables y el DATA LIST 5/)
  end

  it 'un archivo que no es .sav no se puede verificar' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'fake.sav')
      File.write(path, 'contenido sav simulado')

      expect { verify(sav_path: path) }.to raise_error(described_class::UnverifiableError)
    end
  end

  it 'respeta los decimales implicitos del DATA LIST ("X 1-5 (2)" con 00123 vale 1,23)' do
    column = { name: 'X', start: 1, end: 5, format: '2' }
    verifier = described_class.new(sav, sps, dat)

    expect(verifier.send(:equal_number?, column, '00123', 1.23)).to be true
    expect(verifier.send(:equal_number?, column, '1.5', 1.5)).to be true
    expect(verifier.send(:equal_number?, column, '    ', nil)).to be true
    expect(verifier.send(:equal_number?, column, '00123', 123.0)).to be false
  end
end
