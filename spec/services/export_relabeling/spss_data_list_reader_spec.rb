# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe ExportRelabeling::SpssDataListReader do
  # Mismo formato real de Confirmit (confirmado contra p833174000229):
  # RESPONSEID numerico, STATUS alfanumerico, RESPID numerico, con
  # VARIABLE LABELS despues del bloque DATA LIST.
  let(:sps_text) do
    <<~SPS
      FILE HANDLE F1
       /NAME = 'c:\\temp\\data.asc'
       /LRECL=30.
      DATA LIST
       FIXED FILE = F1
       RECORDS=1
      /1
       RESPONSEID 1-8
       STATUS 9-28 (A)
       RESPID 29-30
      .
      VARIABLE LABELS
       RESPONSEID 'responseid'
       STATUS 'status'
       RESPID 'respid'
      .
    SPS
  end

  def write_data_file(lines)
    dir = Dir.mktmpdir
    path = File.join(dir, 'data.asc')
    File.write(path, lines.join("\n") + "\n")
    path
  end

  it 'parsea las posiciones de columna del DATA LIST y trocea el .dat segun esas posiciones' do
    data_path = write_data_file([
      '426     complete            01',
      '336     screened            02'
    ])

    sheet = described_class.call(sps_text: sps_text, data_path: data_path)

    expect(sheet.headers.map(&:variable_name)).to eq(%w[RESPONSEID STATUS RESPID])
    expect(sheet.rows).to eq([
      %w[426 complete 01],
      %w[336 screened 02]
    ])
  end

  it 'usa el texto de VARIABLE LABELS como raw_label de cada header' do
    data_path = write_data_file(['426     complete            01'])

    sheet = described_class.call(sps_text: sps_text, data_path: data_path)

    expect(sheet.headers.map(&:raw_label)).to eq(%w[responseid status respid])
  end

  it 'si una variable no tiene VARIABLE LABELS, usa su propio nombre como raw_label' do
    sin_labels = sps_text.sub(/VARIABLE LABELS.*?\n\.\n/m, '')
    data_path = write_data_file(['426     complete            01'])

    sheet = described_class.call(sps_text: sin_labels, data_path: data_path)

    expect(sheet.headers.map(&:raw_label)).to eq(%w[RESPONSEID STATUS RESPID])
  end

  it 'saca el padding de espacios de las puntas de cada valor, no del medio' do
    data_path = write_data_file(['426     complete two words   01'])

    sheet = described_class.call(sps_text: sps_text, data_path: data_path)

    expect(sheet.rows.first[1]).to eq('complete two words')
  end

  it 'levanta un error si el .sps no tiene ningun DATA LIST reconocible' do
    data_path = write_data_file(['426'])

    expect { described_class.call(sps_text: 'cualquier cosa sin DATA LIST', data_path: data_path) }
      .to raise_error(/No se encontro ningun campo/)
  end
end
