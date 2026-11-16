# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::SpssDataListOrder do
  let(:sps) do
    <<~SPS
      FILE HANDLE F1
       /NAME = 'c:\\temp\\data.asc'
       /LRECL=40.
      DATA LIST
       FIXED FILE = F1
       RECORDS=1
      /1
       RESPONSEID 1-8
       S11X1B_2 9
       S11X1A_1 10-11
       STATUS 12-20 (A)
       S11X1A_2 21
      .
      VARIABLE LABELS
       S11X1A_1 'uno'
      .
    SPS
  end

  let(:lookup) do
    positions = { 's11x1a_1' => [1, 0, 0], 's11x1a_2' => [1, 1, 0], 's11x1b_2' => [2, 1, 0] }
    double('lookup').tap { |l| allow(l).to receive(:column_position) { |name| positions[name.to_s.downcase] } }
  end

  it 'reordena las lineas de variables del DATA LIST segun el cuestionario, con sus columnas intactas' do
    result = described_class.call(sps, lookup)

    # STATUS (que el schema no conoce) se queda en su lugar; las otras 3 se reparten los
    # lugares de las conocidas, en orden de cuestionario.
    expect(result).to include(" RESPONSEID 1-8\n S11X1A_1 10-11\n S11X1A_2 21\n STATUS 12-20 (A)\n S11X1B_2 9\n")
  end

  it 'no toca el resto de la sintaxis (FILE HANDLE, VARIABLE LABELS...)' do
    result = described_class.call(sps, lookup)

    expect(result).to start_with("FILE HANDLE F1\n /NAME = 'c:\\temp\\data.asc'\n /LRECL=40.\nDATA LIST\n FIXED FILE = F1\n RECORDS=1\n/1\n")
    expect(result).to end_with("VARIABLE LABELS\n S11X1A_1 'uno'\n.\n")
  end

  it 'las variables siguen leyendose de las mismas columnas (solo cambia el orden)' do
    original = ExportRelabeling::SpssDataListReader::VARIABLE_DEF
    block = ->(text) { text.each_line.map(&:strip).select { |line| original.match?(line) }.sort }

    expect(block.call(described_class.call(sps, lookup))).to eq(block.call(sps))
  end

  it 'conserva los fines de linea CRLF' do
    result = described_class.call(sps.gsub("\n", "\r\n"), lookup)

    expect(result).to include(" S11X1A_1 10-11\r\n S11X1A_2 21\r\n STATUS 12-20 (A)\r\n")
  end

  it 'sin lookup, o sin nada que reordenar, devuelve el texto tal cual' do
    expect(described_class.call(sps, nil)).to eq(sps)
    without_misplaced = sps.sub(" S11X1B_2 9\n", '')
    expect(described_class.call(without_misplaced, lookup)).to eq(without_misplaced)
  end

  it 'si el .sps no tiene bloque DATA LIST, lo devuelve igual' do
    expect(described_class.call("VARIABLE LABELS\n.\n", lookup)).to eq("VARIABLE LABELS\n.\n")
  end
end
