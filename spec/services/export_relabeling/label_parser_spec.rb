# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::LabelParser do
  # Todos los casos vienen de p573989981944_def_dcasar_585545730.sps, ya
  # des-escapados (comillas simples SPSS '' -> ') como corresponde recibirlos.

  it 'separa un caso simple en codigo, atributo y pregunta' do
    label = "Consultório/Clínica/Hospital PRIVADO (F4 - Dentre os locais de atendimento abaixo, " \
            "como o(a) Dr.(a) distribuiria o seu tempo de atendimento?)"

    expect(described_class.call(label)).to eq(
      code: 'F4',
      attribute: 'Consultório/Clínica/Hospital PRIVADO',
      question: 'Dentre os locais de atendimento abaixo, como o(a) Dr.(a) distribuiria o seu tempo de atendimento?'
    )
  end

  it 'no rompe cuando el propio atributo ya tiene parentesis' do
    label = 'Outras funções profissionais (ex: atividades administrativas no hospital) ' \
            '(F6 - Aproximadamente quanto do seu tempo é dedicado às seguintes atividades? )'

    expect(described_class.call(label)).to eq(
      code: 'F6',
      attribute: 'Outras funções profissionais (ex: atividades administrativas no hospital)',
      question: 'Aproximadamente quanto do seu tempo é dedicado às seguintes atividades?'
    )
  end

  it 'deja el piping simple crudo en el atributo, sin intentar resolverlo' do
    label = "^f('f9_99_other')^ (F9A - E quantas(os) pacientes o(a) Dr.(a) atendeu a partir de " \
            'FEVEREIRO DE 2026 com esse(s) tipo(s) de câncer(es) no ambiente privado? )'

    expect(described_class.call(label)).to eq(
      code: 'F9A',
      attribute: "^f('f9_99_other')^",
      question: 'E quantas(os) pacientes o(a) Dr.(a) atendeu a partir de FEVEREIRO DE 2026 com ' \
                 'esse(s) tipo(s) de câncer(es) no ambiente privado?'
    )
  end

  it 'deja el piping de conteo agregado crudo dentro del atributo' do
    label = "1ª linha de tratamento: (^f('f15r')['1'].toNumber()^ pacientes) " \
            '(Não realizaram esse teste - Não realizaram esse teste)'

    expect(described_class.call(label)).to eq(
      code: 'Não realizaram esse teste',
      attribute: "1ª linha de tratamento: (^f('f15r')['1'].toNumber()^ pacientes)",
      question: 'Não realizaram esse teste'
    )
  end

  it 'cae al fallback de 2 partes cuando el piping condicional no cierra con parentesis al final' do
    label = "Q0b - A instituição pública a qual ^f('q0a').any('a')? 'possui vínculo': " \
            "'possuiu vínculo nos últimos 9 meses'^ tem alguma autoridade ou capacidade de " \
            'influenciar os negócios da IQVIA?'

    expect(described_class.call(label)).to eq(
      code: 'Q0b',
      attribute: nil,
      question: "A instituição pública a qual ^f('q0a').any('a')? 'possui vínculo': " \
                 "'possuiu vínculo nos últimos 9 meses'^ tem alguma autoridade ou capacidade de " \
                 'influenciar os negócios da IQVIA?'
    )
  end

  it 'no confunde un parentesis final que es parte natural de la pregunta con un codigo (Excel real, Q0A)' do
    label = 'Q0a - Você possui vínculo (contratual/empregatício) atual, ou nos últimos 9 meses, ' \
            'com uma instituição pública de qualquer esfera (municipal, estadual ou nacional)?'

    expect(described_class.call(label)).to eq(
      code: 'Q0a',
      attribute: nil,
      question: 'Você possui vínculo (contratual/empregatício) atual, ou nos últimos 9 meses, ' \
                 'com uma instituição pública de qualquer esfera (municipal, estadual ou nacional)?'
    )
  end

  it 'no confunde un marcador de lista tipo "(c)" al final de un texto legal largo con un codigo (Excel real, farmacovigilancia)' do
    label = 'ENTENDA SOBRE OS DEMAIS ASPECTOS ENVOLVIDOS NESTA PESQUISA - 5. Pagamento de Incentivo ' \
            'para Participação. Concordando com este termo: (1) não foi condenado(a); (2) nenhum membro ' \
            'do seu pessoal; (3) nenhum membro, direta ou indiretamente, para: (i) influenciar; (ii) induzir; ' \
            'e, (c)'

    result = described_class.call(label)

    expect(result[:code]).to be_nil
    expect(result[:attribute]).to be_nil
    expect(result[:question]).to eq(label)
  end

  it 'no confunde una aclaracion final tipo "(18)" con un codigo cuando el " - " real esta al principio (Excel real, termo1)' do
    label = '  - 9. Obrigações do(a) entrevistado(a). Assinalando o consentimento, o(a) Sr(a) atesta ' \
            'que tem dezoito (18)'

    expect(described_class.call(label)).to eq(
      code: nil,
      attribute: nil,
      question: '9. Obrigações do(a) entrevistado(a). Assinalando o consentimento, o(a) Sr(a) atesta ' \
                 'que tem dezoito (18)'
    )
  end

  it 'deja intactas las variables de sistema sin patron codigo/atributo' do
    expect(described_class.call('responseid')).to eq(code: nil, attribute: nil, question: 'responseid')
  end

  it 'separa un label de nivel de loop aunque venga duplicado' do
    expect(described_class.call('1ª linha - 1ª linha')).to eq(
      code: '1ª linha',
      attribute: nil,
      question: '1ª linha'
    )
  end

  describe '.reformat' do
    it 'arma el string final "codigo | atributo | pregunta" cuando hay atributo' do
      label = 'Consultório/Clínica/Hospital PRIVADO (F4 - Dentre os locais...)'

      expect(described_class.reformat(label)).to eq(
        'F4 | Consultório/Clínica/Hospital PRIVADO | Dentre os locais...'
      )
    end

    it 'arma el string con atributo vacio cuando no hay grupo final de parentesis' do
      expect(described_class.reformat('Q0b - Alguma pergunta?')).to eq('Q0b |  | Alguma pergunta?')
    end

    it 'deja pasar sin cambios una variable de sistema sin codigo ni atributo' do
      expect(described_class.reformat('responseid')).to eq('responseid')
    end
  end

  describe '.format' do
    it 'arma el string final cuando hay codigo y atributo' do
      parsed = { code: 'F4', attribute: 'Consultório/Clínica/Hospital PRIVADO', question: 'Dentre os locais...' }

      expect(described_class.format(parsed)).to eq('F4 | Consultório/Clínica/Hospital PRIVADO | Dentre os locais...')
    end

    it 'devuelve solo la pregunta cuando no hay codigo ni atributo' do
      expect(described_class.format(code: nil, attribute: nil, question: 'responseid')).to eq('responseid')
    end

    # Bug real: una variable Hidden (ej. "LinkFarmaco") puede resolverse via
    # la API con Title/Text realmente vacios -- {code: nil, attribute: nil,
    # question: nil}, no un "no encontrado". Sin este caso, format devolvia
    # nil, y un llamador que asume un String (ej. SpssSyntaxRewriter,
    # que hace `.gsub` sobre el resultado) rompia con NoMethodError.
    it 'nunca devuelve nil, incluso cuando code/attribute/question estan los 3 vacios' do
      expect(described_class.format(code: nil, attribute: nil, question: nil)).to eq('')
    end
  end
end
