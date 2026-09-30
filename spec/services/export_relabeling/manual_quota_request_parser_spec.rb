# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ManualQuotaRequestParser do
  # Ejemplo real propuesto por Diego, incluido el separador de pares mixto
  # (";" en una linea, espacio en la otra) para validar que el parser no
  # depende de que el PM sea prolijo con la puntuacion.
  let(:body) do
    <<~BODY
      dcasar@fine-research.com;info@fine-research.com

      Quotas:
      S0: 1=50; 2=30; 3=10; 4=5; 5=20
      tipoficha: A=50 B=60
      Report:
      QuotaReg x tipoficha
      tipoficha x qp0

      Saludos,
      Diego
    BODY
  end

  it 'parsea la seccion Quotas: en {variable:, targets: [{precode:, meta:}]}' do
    result = described_class.call(body)

    expect(result[:quotas]).to eq(
      [
        { variable: 'S0', targets: [{ precode: '1', meta: 50 }, { precode: '2', meta: 30 }, { precode: '3', meta: 10 },
                                     { precode: '4', meta: 5 }, { precode: '5', meta: 20 }] },
        { variable: 'tipoficha', targets: [{ precode: 'A', meta: 50 }, { precode: 'B', meta: 60 }] }
      ]
    )
  end

  it 'parsea la seccion Report: en {variable_a:, variable_b:}' do
    result = described_class.call(body)

    expect(result[:crosses]).to eq(
      [
        { variable_a: 'QuotaReg', variable_b: 'tipoficha' },
        { variable_a: 'tipoficha', variable_b: 'qp0' }
      ]
    )
  end

  it 'no rompe si el mail no tiene ninguna de las 2 secciones (caso normal, sin pedido extra)' do
    result = described_class.call("solo.el@destinatario.com\n\nSaludos")

    expect(result).to eq(quotas: [], crosses: [])
  end

  it 'corta la seccion Quotas: apenas encuentra una linea que no matchea (ej. la firma del mail)' do
    body_con_ruido = <<~BODY
      dcasar@fine-research.com

      Quotas:
      S0: 1=50; 2=30

      Gracias, cualquier duda avisenme
      Diego
    BODY

    result = described_class.call(body_con_ruido)

    expect(result[:quotas]).to eq([{ variable: 'S0', targets: [{ precode: '1', meta: 50 }, { precode: '2', meta: 30 }] }])
  end

  it 'acepta coma como separador de pares tambien, no solo punto y coma o espacio' do
    result = described_class.call("Quotas:\nS0: 1=50, 2=30,3=10")

    expect(result[:quotas]).to eq(
      [{ variable: 'S0', targets: [{ precode: '1', meta: 50 }, { precode: '2', meta: 30 }, { precode: '3', meta: 10 }] }]
    )
  end
end
