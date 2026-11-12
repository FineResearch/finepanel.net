# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe ExportRelabeling::SpssDataFilePreparer do
  let(:dir) { Dir.mktmpdir }
  let(:data_path) { File.join(dir, 'data.asc') }

  after { FileUtils.rm_rf(dir) }

  def write_data(bytes)
    File.write(data_path, bytes.b, mode: 'wb')
  end

  def prepare
    described_class.call(data_path)
  end

  # Caso real (p588393362171): PSPP cuenta bytes y Confirmit arma las columnas
  # por caracter, asi que cada tilde (2 bytes en UTF-8) corria las columnas
  # siguientes de esa fila.
  it 'pasa un .asc UTF-8 con tildes a Windows-1252: 1 byte por caracter, las columnas quedan donde dice el .sps' do
    line = "0001#{'Abbrvie você'.ljust(16)}187\n"
    write_data(line.encode('UTF-8'))

    result = prepare

    expect(result.encoding).to eq('Windows-1252')
    expect(result.path).not_to eq(data_path)
    out = File.read(result.path, mode: 'rb')
    expect(out.bytesize).to eq(line.length)
    expect(out.force_encoding('Windows-1252').encode('UTF-8')).to eq(line)
    # Las columnas 21-22 y 23 (despues del texto con tilde) siguen siendo "18" y "7".
    expect(out[20, 2]).to eq('18')
    expect(out[22, 1]).to eq('7')
  end

  it 'conserva el euro y las comillas tipograficas (existen en Windows-1252)' do
    line = "preço € “x”\n"
    write_data(line.encode('UTF-8'))

    out = File.read(prepare.path, mode: 'rb').force_encoding('Windows-1252').encode('UTF-8')

    expect(out).to eq(line)
  end

  it 'reemplaza por un unico "?" lo que Windows-1252 no tiene, sin correr columnas, y lo deja en el log' do
    line = "ab中cd\n" # ideograma chino: no existe en Windows-1252
    write_data(line.encode('UTF-8'))
    allow(Rails.logger).to receive(:warn)

    result = prepare

    expect(File.read(result.path, mode: 'rb')).to eq("ab?cd\n")
    expect(Rails.logger).to have_received(:warn).with(/1 caracter\(es\) sin equivalente/)
  end

  it 'saca el BOM UTF-8 y transcodifica en la misma pasada' do
    write_data("\xEF\xBB\xBFnão\n".b)

    result = prepare

    expect(File.read(result.path, mode: 'rb')).to eq("n\xE3o\n".b)
    expect(result.encoding).to eq('Windows-1252')
  end

  it 'con BOM pero solo ASCII: saca el BOM y no declara encoding' do
    write_data("\xEF\xBB\xBF1 \n".b)

    result = prepare

    expect(File.read(result.path, mode: 'rb')).to eq("1 \n")
    expect(result.encoding).to be_nil
  end

  it 'un .asc solo ASCII sin BOM se compila tal cual (mismo path, sin encoding)' do
    write_data("1 \n")

    result = prepare

    expect(result.path).to eq(data_path)
    expect(result.encoding).to be_nil
  end

  it 'un archivo que no es UTF-8 valido no se toca: no se sabe que son esos bytes' do
    write_data("n\xE3o\n".b)

    result = prepare

    expect(result.path).to eq(data_path)
    expect(result.encoding).to be_nil
    expect(File.read(data_path, mode: 'rb')).to eq("n\xE3o\n".b)
  end

  it 'nunca modifica el archivo original' do
    original = "0001você \n".encode('UTF-8')
    write_data(original)

    prepare

    expect(File.read(data_path, mode: 'rb')).to eq(original.b)
  end
end
