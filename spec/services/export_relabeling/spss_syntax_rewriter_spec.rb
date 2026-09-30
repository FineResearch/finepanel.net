# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::SpssSyntaxRewriter do
  # Sintaxis chica pero con la misma forma exacta que un .sps real de
  # Confirmit (comillas simples escapadas como '', bloques terminados en
  # ".", VALUE LABELS con sub-bloques separados por "/") -- ver
  # p573989981944_def_dcasar_585545730.sps para el archivo completo del
  # que salen estos casos.
  let(:sps_text) do
    <<~SPS
      FILE HANDLE F123
       /NAME = 'c:\\temp\\test.asc'
       /LRECL=100.
      DATA LIST
       FIXED FILE = F123
       RECORDS=1
      /1
       RESPONSEID 1-8
       F4_1 9-11
       F9A_99 12-15
      .
      VARIABLE LABELS
       RESPONSEID ''
       F4_1 'Consultório/Clínica/Hospital PRIVADO (F4 - Dentre os locais de atendimento abaixo, como o(a) Dr.(a) distribuiria o seu tempo de atendimento?)'
       F9A_99 '^f(''f9_99_other'')^ (F9A - E quantas(os) pacientes o(a) Dr.(a) atendeu a partir de FEVEREIRO DE 2026 com esse(s) tipo(s) de câncer(es) no ambiente privado? )'
      .
      VALUE LABELS
       F4_1
        1 'Câncer de Colo do Útero (F9 - Pensando em sua prática clínica, qual(is) o(s) tipo(s) de câncer(es) abaixo o(a) Dr(a) costuma tratar no ambiente privado? )'
       /
      .
      LIST.
    SPS
  end

  subject(:rewritten) { described_class.call(sps_text) }

  it 'no toca nada antes del bloque VARIABLE LABELS (FILE HANDLE, DATA LIST)' do
    expect(rewritten).to include("FILE HANDLE F123")
    expect(rewritten).to include(" RESPONSEID 1-8")
    expect(rewritten).to include(" F4_1 9-11")
  end

  it 'deja intacta una variable de sistema sin patron detectable' do
    expect(rewritten).to include(" RESPONSEID ''")
  end

  it 'reescribe un label compuesto simple dentro de VARIABLE LABELS' do
    expect(rewritten).to include(
      " F4_1 'F4 | Consultório/Clínica/Hospital PRIVADO | Dentre os locais de atendimento abaixo, " \
      "como o(a) Dr.(a) distribuiria o seu tempo de atendimento?'"
    )
  end

  it 'deja el piping crudo, re-escapado correctamente, dentro de VARIABLE LABELS' do
    expect(rewritten).to include(
      " F9A_99 'F9A | ^f(''f9_99_other'')^ | E quantas(os) pacientes o(a) Dr.(a) atendeu a partir de " \
      "FEVEREIRO DE 2026 com esse(s) tipo(s) de câncer(es) no ambiente privado?'"
    )
  end

  it 'usa el lookup (API) en vez de LabelParser dentro de VARIABLE LABELS cuando lo encuentra' do
    # El token le llega al lookup tal cual aparece en el .sps (MAYUSCULA) --
    # la conversion a minuscula para matchear el schema pasa DENTRO de
    # ConfirmitVariableLookup, no en el resolver ni en el rewriter.
    lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
    allow(lookup).to receive(:call).and_return(nil)
    allow(lookup).to receive(:call).with('F4_1').and_return(code: 'F4', attribute: 'Atributo de la API', question: 'Pregunta de la API')

    result = described_class.call(sps_text, lookup: lookup)

    expect(result).to include(" F4_1 'F4 | Atributo de la API | Pregunta de la API'")
  end

  it 'no usa el lookup dentro de VALUE LABELS (el token ahi es un codigo de respuesta, no una variable)' do
    lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
    allow(lookup).to receive(:call).and_return(nil)

    described_class.call(sps_text, lookup: lookup)

    expect(lookup).not_to have_received(:call).with('1')
  end

  it 'reescribe el mismo tipo de label compuesto dentro de VALUE LABELS' do
    expect(rewritten).to include(
      "  1 'F9 | Câncer de Colo do Útero | Pensando em sua prática clínica, qual(is) o(s) tipo(s) de " \
      "câncer(es) abaixo o(a) Dr(a) costuma tratar no ambiente privado?'"
    )
  end

  it 'deja intactas la linea de variable y el separador "/" dentro de VALUE LABELS' do
    expect(rewritten).to include(" F4_1\n")
    expect(rewritten).to include(" /\n")
  end

  it 'no toca nada despues del "." final de VALUE LABELS' do
    expect(rewritten).to include("LIST.")
  end

  it 'mantiene la misma cantidad de lineas que el original' do
    expect(rewritten.lines.count).to eq(sps_text.lines.count)
  end

  # Bug real: un texto legal largo resuelto via la API (ej.
  # "farmacovigilancia"/"termo1") puede traer saltos de linea reales (el
  # HTML de origen tiene varios <p>) -- un salto de linea literal DENTRO
  # de un string entre comillas rompe la sintaxis de SPSS ("Unterminated
  # string constant", confirmado contra PSPP real). Confirmit mismo
  # colapsa esos saltos a un espacio en su propio .sps -- el rewriter
  # tiene que hacer lo mismo con el texto que trae la API.
  it 'colapsa saltos de linea reales del texto resuelto por la API a un espacio, sin romper la sintaxis' do
    lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
    allow(lookup).to receive(:call).and_return(nil)
    allow(lookup).to receive(:call).with('RESPONSEID').and_return(
      code: nil, attribute: nil, question: "9. Obrigações\nQuando aplicável, é sua obrigação...\n10. Propriedade"
    )

    result = described_class.call(sps_text, lookup: lookup)
    rewritten_line = result.lines.find { |line| line.include?('9. Obrigações') }

    expect(rewritten_line).to eq(" RESPONSEID '9. Obrigações Quando aplicável, é sua obrigação... 10. Propriedade'\n")
  end
end
