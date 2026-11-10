# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::MissingVariablesDetector do
  def lookup_with(units)
    instance_double(ExportRelabeling::ConfirmitVariableLookup).tap do |lookup|
      allow(lookup).to receive(:questionnaire_variables)
        .with(start_markers: %w[presentation presentacion], end_marker: 'iradatos1').and_return(units)
    end
  end

  let(:units) do
    [
      { name: 'f0', title: 'F0', names: %w[f0] },
      { name: 'i3', title: 'I3', names: %w[i3] },
      { name: 'q5a', title: 'Q5A', names: %w[q5a] },
      { name: 'gf18', title: 'F18', names: %w[gf18 f18x1 f18x2] }
    ]
  end

  it 'avisa solo las preguntas que no tienen ninguna columna exportada' do
    result = described_class.call(lookup: lookup_with(units), exported_names: %w[responseid f0 i3_1 i3_2 f18x1_1])

    expect(result).to eq([{ name: 'q5a', title: 'Q5A' }])
  end

  it 'una columna "<variable>_<algo>" alcanza (opcion de Multi/Grid, _other, fila de Grid3D)' do
    result = described_class.call(lookup: lookup_with(units), exported_names: %w[f0 i3_99_other q5a_3 f18x2_1])

    expect(result).to eq([])
  end

  it 'compara sin importar mayusculas (el .sps trae nombres en mayuscula, el schema en minuscula)' do
    result = described_class.call(lookup: lookup_with(units), exported_names: %w[F0 I3_1 Q5A GF18_1])

    expect(result).to eq([])
  end

  it 'no confunde una variable con otra que solo empieza igual (q5 no es q5a)' do
    units = [{ name: 'q5', title: nil, names: %w[q5] }]

    result = described_class.call(lookup: lookup_with(units), exported_names: %w[q5a q50_1])

    expect(result).to eq([{ name: 'q5', title: nil }])
  end

  it 'respeta el orden del cuestionario' do
    result = described_class.call(lookup: lookup_with(units), exported_names: %w[responseid])

    expect(result.map { |variable| variable[:name] }).to eq(%w[f0 i3 q5a gf18])
  end

  it 'no avisa los textos legales de consentimiento (termo, termo1, farmacovigilancia)' do
    units = [
      { name: 'termo', title: nil, names: %w[termo] },
      { name: 'termo1', title: nil, names: %w[termo1] },
      { name: 'Farmacovigilancia', title: nil, names: %w[farmacovigilancia] },
      { name: 'termometro', title: nil, names: %w[termometro] }
    ]

    result = described_class.call(lookup: lookup_with(units), exported_names: %w[responseid])

    expect(result.map { |variable| variable[:name] }).to eq(%w[termometro])
  end

  it 'no avisa nada si no hay lookup' do
    expect(described_class.call(lookup: nil, exported_names: %w[f0])).to eq([])
  end

  it 'no avisa nada si el schema no trae los marcadores (no se puede acotar, evita falsas alarmas)' do
    expect(described_class.call(lookup: lookup_with(nil), exported_names: %w[f0])).to eq([])
  end
end
