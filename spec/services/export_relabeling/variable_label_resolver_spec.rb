# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::VariableLabelResolver do
  it 'usa el resultado del lookup cuando lo encuentra, sin tocar LabelParser' do
    lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
    allow(lookup).to receive(:call).with('f4_1').and_return(code: 'F4', attribute: 'Atributo API', question: 'Pregunta API')

    result = described_class.call(variable_name: 'f4_1', raw_label: 'cualquier cosa (F4 - lo que sea)', lookup: lookup)

    expect(result).to eq(code: 'F4', attribute: 'Atributo API', question: 'Pregunta API')
  end

  it 'cae a LabelParser cuando el lookup no encuentra la variable' do
    lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
    allow(lookup).to receive(:call).with('responseid').and_return(nil)

    result = described_class.call(variable_name: 'responseid', raw_label: 'responseid', lookup: lookup)

    expect(result).to eq(code: nil, attribute: nil, question: 'responseid')
  end

  it 'cae a LabelParser directo cuando no hay lookup (nil)' do
    result = described_class.call(
      variable_name: 'f4_1',
      raw_label: 'Atributo (F4 - Pregunta)',
      lookup: nil
    )

    expect(result).to eq(code: 'F4', attribute: 'Atributo', question: 'Pregunta')
  end

  # Confirmado contra variables Hidden/de sistema reales (ej.
  # "LinkFarmaco", "FechaCompleta"): la API las "encuentra" en el schema
  # pero sin Title/Text configurado (nunca se le muestran al
  # respondiente) -- un hash {question: nil} no es "no encontrado", pero
  # aceptarlo tal cual borraba el label que el export YA traia crudo.
  it 'cae a LabelParser cuando el lookup encuentra la variable pero con el texto vacio (Hidden/sistema)' do
    lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
    allow(lookup).to receive(:call).with('linkfarmaco').and_return(code: nil, attribute: nil, question: nil)

    result = described_class.call(variable_name: 'linkfarmaco', raw_label: 'LinkFarmaco', lookup: lookup)

    expect(result).to eq(code: nil, attribute: nil, question: 'LinkFarmaco')
  end

  it 'lo mismo si el lookup devuelve question como string vacio (no nil)' do
    lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
    allow(lookup).to receive(:call).with('fechacompleta').and_return(code: nil, attribute: nil, question: '')

    result = described_class.call(variable_name: 'fechacompleta', raw_label: 'FechaCompleta', lookup: lookup)

    expect(result).to eq(code: nil, attribute: nil, question: 'FechaCompleta')
  end
end
