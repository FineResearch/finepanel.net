# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::QuotaProgressBuilder do
  let(:header_class) { ExportRelabeling::ExcelReader::Header }

  # Archivo principal: 1 fila por entrevistado. status/complete son los
  # nombres reales confirmados contra un proyecto real (p573989981944).
  let(:main_source) do
    {
      headers: [header_class.new('status', 'status'), header_class.new('llegoafin', 'llegoafin'), header_class.new('s0', 's0')],
      rows: [
        %w[complete 1 1],
        %w[complete 1 2],
        %w[complete 2 1],
        %w[screened 1 1] # no cuenta -- no esta completo
      ],
      status_variable: 'status',
      complete_value: 'complete'
    }
  end

  # Archivo de fichas: 1 fila por ficha, puede haber varias por entrevistado
  # -- "fichaestado"/"completa" son los nombres reales confirmados contra
  # el archivo de fichas de p573989981944 (distinto al "status"/"complete"
  # del archivo principal).
  let(:fichas_source) do
    {
      headers: [header_class.new('fichaestado', 'fichaestado'), header_class.new('qestado_1', 'qestado_1')],
      rows: [
        %w[completa 1],
        %w[completa 2],
        %w[completa 3],
        %w[completa 1], # 2da ficha del mismo entrevistado, cuenta aparte
        %w[incompleta 1] # no cuenta -- no esta completa
      ],
      status_variable: 'fichaestado',
      complete_value: 'completa'
    }
  end

  let(:sources) { [main_source, fichas_source] }

  def blank_row
    Array.new(described_class::HEADER.length)
  end

  it 'la celda sin QuotaField (meta total) cuenta status=complete del archivo principal' do
    quotas = [{ name: 'quota4', cells: [{ limit: 2997, fields: [] }] }]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result[:rows]).to eq([described_class::HEADER, ['quota4', '(total)', '-', 2997, 3, 2994]])
    expect(result[:header_indices]).to eq([0])
  end

  it 'una variable fuera del loop NO colapsa -- cada valor es su propia meta independiente, con Quota/Variable en blanco a partir de la 2da fila del grupo' do
    quotas = [
      {
        name: 'quota1',
        cells: [
          { limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] },
          { limit: 43, fields: [{ name: 's0', precode: nil, value: '2' }] }
        ]
      }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result[:rows]).to eq(
      [
        described_class::HEADER,
        ['quota1', 's0', '1', 88, 2, 86],
        [nil, nil, '2', 43, 1, 42]
      ]
    )
  end

  it 'una variable del loop SI colapsa -- una sola fila, meta de la primera linea, cuenta cualquiera de los valores' do
    quotas = [
      {
        name: 'quota5',
        cells: [
          { limit: 34, fields: [{ name: 'qestado_1', precode: '1', value: '1' }] },
          { limit: 99, fields: [{ name: 'qestado_1', precode: '1', value: '2' }] }, # limite distinto, se ignora
          { limit: 55, fields: [{ name: 'qestado_1', precode: '1', value: '3' }] }
        ]
      }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    # 3 fichas completas con qestado_1 en {1,2,3} -- la 4ta fila del fixture
    # (qestado_1=1) tambien matchea, son 3 completas con valor en el set +
    # la ficha "1" repetida = 4to match.
    expect(result[:rows]).to eq([described_class::HEADER, ['quota5', 'qestado_1', '1, 2, 3', 34, 4, 30]])
  end

  # Diego: las cuotas declaradas a mano por un PM en el mail (ej. "tipoficha:
  # A=50 B=60") nunca deben colapsar, aunque la variable viva en el loop --
  # el PM puso una meta especifica por precode a proposito.
  it 'con collapse_loop_quotas: false, una variable del loop NO colapsa -- una fila por celda igual' do
    quotas = [
      {
        name: 'tipoficha',
        cells: [
          { limit: 50, fields: [{ name: 'qestado_1', precode: nil, value: '1' }] },
          { limit: 60, fields: [{ name: 'qestado_1', precode: nil, value: '2' }] }
        ]
      }
    ]

    result = described_class.call(quotas: quotas, sources: sources, collapse_loop_quotas: false)

    expect(result[:rows]).to eq(
      [
        described_class::HEADER,
        ['tipoficha', 'qestado_1', '1', 50, 2, 48],
        [nil, nil, '2', 60, 1, 59]
      ]
    )
  end

  it 'una cuota cruzada (2+ campos) del mismo archivo cuenta con AND entre los campos' do
    quotas = [
      {
        name: 'quota_cruzada',
        cells: [{ limit: 180, fields: [{ name: 'llegoafin', precode: nil, value: '1' }, { name: 's0', precode: nil, value: '1' }] }]
      }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result[:rows]).to eq([described_class::HEADER, ['quota_cruzada', 'llegoafin + s0', '1 + 1', 180, 1, 179]])
  end

  it 'una cuota cruzada entre el archivo principal y el de loop se marca para revisar a mano, no se adivina' do
    quotas = [
      {
        name: 'quota_imposible',
        cells: [{ limit: 50, fields: [{ name: 's0', precode: nil, value: '1' }, { name: 'qestado_1', precode: '1', value: '1' }] }]
      }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result[:rows]).to eq(
      [
        described_class::HEADER,
        ['quota_imposible', 's0 + qestado_1', '1 + 1', 50, described_class::CROSS_SOURCE_UNSUPPORTED, nil]
      ]
    )
  end

  it 'una cuota con una variable que no existe en ningun archivo exportado se excluye por completo del reporte' do
    quotas = [{ name: 'quota_x', cells: [{ limit: 10, fields: [{ name: 'no_existe', precode: nil, value: '1' }] }] }]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result).to eq(rows: [], header_indices: [])
  end

  # Diego: "chequear previamente que todas las variables de la cuota esten
  # presentes... si alguna no esta se excluye el reporte de esa cuota" --
  # todo o nada por Quota COMPLETA, no por celda: si una celda de la
  # misma Quota si resuelve pero otra no, igual se excluyen las dos (no
  # mostrar un progreso parcial que de una idea enganosa de cobertura).
  it 'si UNA celda de la cuota tiene una variable no encontrada, se excluyen TODAS las celdas de esa cuota (no solo la afectada)' do
    quotas = [
      {
        name: 'quota_mixta',
        cells: [
          { limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] }, # esta si se encuentra
          { limit: 10, fields: [{ name: 'no_existe', precode: nil, value: '1' }] } # esta no
        ]
      }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result).to eq(rows: [], header_indices: [])
  end

  it 'una cuota sin ningun problema de variables no se ve afectada por otra cuota que si tiene una faltante' do
    quotas = [
      { name: 'quota_ok', cells: [{ limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] }] },
      { name: 'quota_rota', cells: [{ limit: 10, fields: [{ name: 'no_existe', precode: nil, value: '1' }] }] }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result[:rows]).to eq([described_class::HEADER, ['quota_ok', 's0', '1', 88, 2, 86]])
    expect(result[:header_indices]).to eq([0])
  end

  it 'ordena las cuotas por orden natural (quota2 antes que quota10, no alfabetico puro)' do
    quotas = [
      { name: 'quota10', cells: [{ limit: 43, fields: [{ name: 's0', precode: nil, value: '2' }] }] },
      { name: 'quota2', cells: [{ limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] }] }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    nombres_en_orden = result[:rows].reject { |row| row.first.nil? || row == described_class::HEADER }.map(&:first)
    expect(nombres_en_orden).to eq(%w[quota2 quota10])
  end

  # El header (Quota | Variable | Value | Goal | Achieved | Pending) se
  # repite en negrita + fondo amarillo (ver ExcelWriter) al principio de
  # CADA bloque -- header_indices apunta a esas filas, para que el llamador
  # sepa cuales resaltar.
  it 'repite el header al principio de cada bloque de cuota, separados por una fila en blanco' do
    quotas = [
      { name: 'quota1', cells: [{ limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] }] },
      { name: 'quota2', cells: [{ limit: 43, fields: [{ name: 's0', precode: nil, value: '2' }] }] }
    ]

    result = described_class.call(quotas: quotas, sources: sources)

    expect(result[:rows]).to eq(
      [
        described_class::HEADER,
        ['quota1', 's0', '1', 88, 2, 86],
        blank_row,
        described_class::HEADER,
        ['quota2', 's0', '2', 43, 1, 42]
      ]
    )
    expect(result[:header_indices]).to eq([0, 3])
  end

  # Bug real: el <Value> de un QuotaField es el PRECODE ("1"), pero el Data
  # Template de un proyecto real (p314244165357) exporta el TEXTO de la
  # respuesta ("MSD"), no el numero -- matchear contra el precode crudo
  # nunca encontraba nada (todo en 0). ConfirmitVariableLookup#quotas ya
  # resuelve `label:` para estos casos -- QuotaProgressBuilder tiene que
  # preferirlo sobre `value` tanto para contar como para mostrar.
  context 'cuando el export trae el TEXTO de la respuesta, no el precode (ver ConfirmitVariableLookup#quotas)' do
    let(:main_source_con_labels) do
      {
        headers: [header_class.new('status', 'status'), header_class.new('hidden_s132', 'hidden_s132')],
        rows: [
          ['complete', 'MSD'],
          ['complete', 'MSD'],
          ['complete', 'nao MSD'],
          ['screened', 'MSD'] # no cuenta -- no esta completo
        ],
        status_variable: 'status',
        complete_value: 'complete'
      }
    end

    it 'cuenta y muestra el label resuelto, no el precode crudo' do
      quotas = [
        {
          name: 'quota4',
          cells: [
            { limit: 180, fields: [{ name: 'hidden_s132', precode: nil, value: '1', label: 'MSD' }] },
            { limit: 99, fields: [{ name: 'hidden_s132', precode: nil, value: '2', label: 'nao MSD' }] }
          ]
        }
      ]

      result = described_class.call(quotas: quotas, sources: [main_source_con_labels])

      expect(result[:rows]).to eq(
        [
          described_class::HEADER,
          ['quota4', 'hidden_s132', 'MSD', 180, 2, 178],
          [nil, nil, 'nao MSD', 99, 1, 98]
        ]
      )
    end
  end
end
