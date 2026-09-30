# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportRelabeling::ConfirmitVariableLookup do
  # Fragmentos basados en la forma real confirmada contra un schema real
  # (GetQuestionnaire de p573989981944) -- ver el comentario de la clase.
  # El "schema" real no es XML valido por si solo (varios elementos raiz
  # hermanos), asi que se prueba tal cual, sin envolverlo antes -- eso lo
  # hace la clase misma.
  let(:schema_xml) do
    <<~XML
      <Single EntityId="19658"><Name>q0b</Name><FormTexts><FormText Language="1046">
        <Title>Q0b</Title>
        <Text>A institui&#231;&#227;o p&#250;blica a qual &lt;strong&gt;^f('q0a').any('a')?^&lt;/strong&gt; tem alguma autoridade?</Text>
      </FormText></FormTexts></Single>
      <Single EntityId="18851"><Name>termo1</Name><FormTexts><FormText Language="1046">
        <Title></Title>
        <Text>&lt;p&gt;&lt;strong&gt;9. Obriga&#231;&#245;es&lt;/strong&gt;&lt;/p&gt;&lt;p&gt;Texto legal completo.&lt;/p&gt;</Text>
      </FormText></FormTexts></Single>
      <Multi EntityId="17621"><Name>f4</Name><FormTexts><FormText Language="1046">
        <Title>F4</Title>
        <Text>Dentre os locais de atendimento, como o(a) Dr.(a) distribuiria seu tempo?</Text>
      </FormText></FormTexts>
        <MultiAnswers EntityId="">
          <Answer Precode="1"><Texts><Text Language="1046">Consult&#243;rio/Cl&#237;nica/Hospital PRIVADO</Text></Texts></Answer>
          <Answer Precode="2"><Texts><Text Language="1046">Consult&#243;rio/Cl&#237;nica/Hospital P&#218;BLICO</Text></Texts></Answer>
        </MultiAnswers>
      </Multi>
      <Grid EntityId="19734"><Name>p2</Name><FormTexts><FormText Language="1046">
        <Title>P2.</Title>
        <Text>Para cada uma das ind&#250;strias farmac&#234;uticas, indique a probabilidade:</Text>
      </FormText></FormTexts>
        <GridAnswers>
          <GridAnswer Precode="1" FieldId="0"><Texts><Text Language="1046">Abbvie</Text></Texts></GridAnswer>
          <GridAnswer Precode="2" FieldId="0"><Texts><Text Language="1046">AstraZeneca</Text></Texts></GridAnswer>
        </GridAnswers>
      </Grid>
      <Multi EntityId="19740"><Name>qfichas</Name><FormTexts><FormText Language="1046">
        <Text>N&#250;mero de Fichas</Text>
      </FormText></FormTexts>
        <MultiAnswers EntityId="">
          <Predefined ListSource="19742" ReferencedEntityId="19742" />
        </MultiAnswers>
      </Multi>
      <PredefinedList EntityId="19742" SourceEntityUrn="urn:confirmit:projects:p947224044708:18670">
        <PredefinedListAnswers>
          <Answer Precode="a"><Texts><Text Language="1046">Fichas 1&#170; linha</Text></Texts></Answer>
          <Answer Precode="b"><Texts><Text Language="1046">Fichas 2&#170; linha</Text></Texts></Answer>
        </PredefinedListAnswers>
        <Name>list_tiposficha2</Name>
      </PredefinedList>
      <PredefinedList EntityId="17686"><PredefinedListAnswers>
        <Predefined ListSource="17685" />
        <Answer Precode="99" Other="true"><Texts><Text Language="1046">Outros - Especifique</Text></Texts></Answer>
      </PredefinedListAnswers><Name>list_s91</Name></PredefinedList>
      <PredefinedList EntityId="17685"><PredefinedListAnswers>
        <Answer Precode="1"><Texts><Text Language="1046">C&#226;ncer de Colo do &#218;tero</Text></Texts></Answer>
      </PredefinedListAnswers><Name>list_tipos_cancer</Name></PredefinedList>
      <Multi EntityId="17638"><Name>f9</Name><FormTexts><FormText Language="1046">
        <Title>F9</Title>
        <Text>Quais tipos de c&#226;ncer?</Text>
      </FormText></FormTexts>
        <MultiAnswers EntityId=""><Predefined ListSource="17686" /></MultiAnswers>
      </Multi>
      <Grid3D EntityId="19731"><Name>gf18</Name><FormTexts><FormText Language="1046">
        <Title>F18</Title>
        <Text>Titulo del Grid3D, no se usa para las filas</Text>
      </FormText></FormTexts>
        <Nodes>
          <Multi EntityId="19727"><Name>f18x1</Name><FormTexts><FormText Language="1046">
            <Text>N&#227;o realizaram esse teste</Text>
          </FormText></FormTexts>
            <MultiAnswers EntityId="" />
          </Multi>
        </Nodes>
        <Grid3DAnswers EntityId="">
          <Answer Precode="1"><Texts><Text Language="1046">1&#170; linha de tratamento</Text></Texts></Answer>
        </Grid3DAnswers>
      </Grid3D>
      <Grid3D EntityId="19709"><Name>gf17s</Name><FormTexts><FormText Language="1046">
        <Title>F17.S</Title>
        <Text>Qual o tratamento de escolha para pacientes PLATINO-SENS&#205;VEIS?</Text>
      </FormText></FormTexts>
        <Nodes>
          <Single EntityId="19710"><Name>f17s1</Name><FormTexts><FormText Language="1046">
            <Text>Linha 1</Text>
          </FormText></FormTexts></Single>
        </Nodes>
        <Grid3DAnswers EntityId="">
          <Answer Precode="1"><Texts><Text Language="1046">Avastin + Quimioterapia</Text></Texts></Answer>
          <Answer Precode="98" Other="true"><Texts><Text Language="1046">Outros, especifique:</Text></Texts></Answer>
        </Grid3DAnswers>
      </Grid3D>
      <Open EntityId="20069" VariableType="Hidden"><Name>LinkFarmaco</Name><FormTexts><FormText Language="1046">
        <Text />
      </FormText></FormTexts></Open>
      <Folder EntityId="20093"><Nodes /><Descriptions><Description Language="1046" /></Descriptions><Name>farmacovigilancia</Name></Folder>
      <Single EntityId="18849"><Name>farmacovigilancia</Name><FormTexts><FormText Language="1046">
        <Title>Farmacovigilancia</Title>
        <Text>Texto legal real de farmacovigilancia.</Text>
      </FormText></FormTexts></Single>
      <Single EntityId="17202"><Name>llegoafin</Name><FormTexts><FormText Language="1046">
        <Title>Completas</Title>
        <Text>Completa at&#233; o final</Text>
      </FormText></FormTexts>
        <SingleAnswers>
          <Answer Precode="1"><Texts><Text Language="1046">Completa at&#233; o final</Text></Texts></Answer>
        </SingleAnswers>
      </Single>
      <Single EntityId="17811" VariableType="Hidden"><Name>fichaestado</Name><FormTexts><FormText Language="1046">
        <Text />
      </FormText></FormTexts>
        <SingleAnswers>
          <Answer Precode="1"><Texts><Text Language="1046">incompleta</Text></Texts></Answer>
          <Answer Precode="2"><Texts><Text Language="1046">completa</Text></Texts></Answer>
          <Answer Precode="3"><Texts><Text Language="1046">invalida</Text></Texts></Answer>
        </SingleAnswers>
      </Single>
      <Quota EntityId="2931429746"><Name>quota1</Name><QuotaLimits>
        <QuotaLimit QuotaLimitId="6"><Limit>180</Limit><QuotaFields>
          <QuotaField ReferencedEntityId="17202"><Name>llegoafin</Name><Value>1</Value></QuotaField>
        </QuotaFields></QuotaLimit>
      </QuotaLimits></Quota>
      <Quota EntityId="16857"><Name>quota4</Name><QuotaLimits>
        <QuotaLimit QuotaLimitId="1"><Limit>2997</Limit><QuotaFields /></QuotaLimit>
      </QuotaLimits></Quota>
      <Quota EntityId="16858"><Name>quota5</Name><QuotaLimits>
        <QuotaLimit QuotaLimitId="4"><Limit>34</Limit><QuotaFields>
          <QuotaField ReferencedEntityId="19818"><Name>qestado_1</Name><Precode>1</Precode><Value>1</Value></QuotaField>
        </QuotaFields></QuotaLimit>
        <QuotaLimit QuotaLimitId="5"><Limit>34</Limit><QuotaFields>
          <QuotaField ReferencedEntityId="19818"><Name>qestado_1</Name><Precode>1</Precode><Value>2</Value></QuotaField>
        </QuotaFields></QuotaLimit>
      </QuotaLimits></Quota>
    XML
  end

  subject(:lookup) { described_class.new(schema_xml) }

  it 'resuelve una pregunta standalone (Single) con codigo y pregunta ya separados y sin HTML' do
    expect(lookup.call('q0b')).to eq(
      code: 'Q0b',
      attribute: nil,
      question: "A instituição pública a qual ^f('q0a').any('a')?^ tem alguma autoridade?"
    )
  end

  it 'devuelve codigo nil cuando el Title de origen esta vacio (texto legal sin codigo real), y limpia el HTML de la pregunta' do
    result = lookup.call('termo1')

    expect(result[:code]).to be_nil
    expect(result[:question]).not_to include('<p>', '<strong>')
    expect(result[:question]).to include('9. Obrigações').and include('Texto legal completo.')
  end

  it 'resuelve una sub-respuesta de una variable Multi por su Precode (ej. f4_1 -> padre f4, Answer 1)' do
    expect(lookup.call('f4_1')).to eq(
      code: 'F4',
      attribute: 'Consultório/Clínica/Hospital PRIVADO',
      question: 'Dentre os locais de atendimento, como o(a) Dr.(a) distribuiria seu tempo?'
    )
    expect(lookup.call('f4_2')[:attribute]).to eq('Consultório/Clínica/Hospital PÚBLICO')
  end

  it 'resuelve una sub-respuesta de una variable Grid por su Precode (estructura distinta a Multi)' do
    expect(lookup.call('p2_1')).to eq(
      code: 'P2.',
      attribute: 'Abbvie',
      question: 'Para cada uma das indústrias farmacêuticas, indique a probabilidade:'
    )
  end

  it 'resuelve una sub-respuesta cuyas opciones vienen por referencia a una PredefinedList compartida, no inline (ej. qfichas)' do
    expect(lookup.call('qfichas_a')).to eq(
      code: nil,
      attribute: 'Fichas 1ª linha',
      question: 'Número de Fichas'
    )
    expect(lookup.call('qfichas_b')[:attribute]).to eq('Fichas 2ª linha')
  end

  it 'resuelve una sub-respuesta cuya PredefinedList reenvia a OTRA PredefinedList (2 niveles, ej. f9/list_s91/list_tipos_cancer)' do
    expect(lookup.call('f9_1')).to eq(
      code: 'F9',
      attribute: 'Câncer de Colo do Útero',
      question: 'Quais tipos de câncer?'
    )
  end

  it 'resuelve el sufijo "_other" delegando a la misma entrada de su opcion base (texto abierto de "especificar")' do
    expect(lookup.call('f9_99_other')).to eq(
      code: 'F9',
      attribute: 'Outros - Especifique',
      question: 'Quais tipos de câncer?'
    )
    expect(lookup.call('f9_99_other')).to eq(lookup.call('f9_99'))
  end

  it 'resuelve una fila de un Grid3D subiendo al ancestro (ej. f18x1_1 -> Grid3D gf18, no la Multi propia vacia)' do
    expect(lookup.call('f18x1_1')).to eq(
      code: 'F18',
      attribute: '1ª linha de tratamento',
      question: 'Não realizaram esse teste'
    )
  end

  it 'resuelve el "_other" de un Grid3D cuando el precode vive directo en el Grid3D (no en una fila anidada, ej. gf17s_98_other)' do
    expect(lookup.call('gf17s_98_other')).to eq(
      code: 'F17.S',
      attribute: 'Outros, especifique:',
      question: 'Qual o tratamento de escolha para pacientes PLATINO-SENSÍVEIS?'
    )
  end

  it 'es case-insensitive (el .sps trae nombres en MAYUSCULA, el schema los guarda en minuscula)' do
    expect(lookup.call('Q0B')).to eq(lookup.call('q0b'))
    expect(lookup.call('F4_1')).to eq(lookup.call('f4_1'))
  end

  it 'encuentra la variable aunque el propio <Name> del schema NO este en minuscula (ej. "LinkFarmaco", variable Hidden armada a mano)' do
    expect(lookup.call('linkfarmaco')).to eq(code: nil, attribute: nil, question: nil)
    expect(lookup.call('LinkFarmaco')).to eq(lookup.call('linkfarmaco'))
  end

  it 'prioriza el nodo de pregunta real cuando el mismo nombre existe tambien en un Folder de logica de ramificacion (ej. "farmacovigilancia")' do
    expect(lookup.call('farmacovigilancia')).to eq(
      code: 'Farmacovigilancia',
      attribute: nil,
      question: 'Texto legal real de farmacovigilancia.'
    )
  end

  it 'devuelve nil para una variable que no existe ni como directa ni como sub-respuesta' do
    expect(lookup.call('responseid')).to be_nil
    expect(lookup.call('f4_99')).to be_nil
  end

  describe '#quotas' do
    it 'devuelve cada Quota con su nombre y sus celdas (limite + variables/valores), resolviendo el label del precode' do
      result = lookup.quotas

      # "llegoafin" SI tiene un nodo Single real con SingleAnswers en el
      # fixture -- confirma que el label se resuelve, no solo el precode
      # crudo (ver el comentario de #quotas: el export real a veces trae
      # el TEXTO, no el numero).
      quota1 = result.find { |q| q[:name] == 'quota1' }
      expect(quota1[:cells]).to eq(
        [{ limit: 180, fields: [{ name: 'llegoafin', precode: nil, value: '1', label: 'Completa até o final' }] }]
      )
    end

    it 'una celda sin QuotaField (meta total del proyecto) devuelve fields vacio, no rompe' do
      quota4 = lookup.quotas.find { |q| q[:name] == 'quota4' }

      expect(quota4[:cells]).to eq([{ limit: 2997, fields: [] }])
    end

    it 'una celda con Precode Y Value distintos (sub-respuesta de Multi, ej. qestado_1) devuelve los dos tal cual' do
      quota5 = lookup.quotas.find { |q| q[:name] == 'quota5' }

      # "qestado" no tiene un nodo propio en el fixture (solo se referencia
      # desde la Quota) -- label queda nil, no rompe.
      expect(quota5[:cells]).to eq(
        [
          { limit: 34, fields: [{ name: 'qestado_1', precode: '1', value: '1', label: nil }] },
          { limit: 34, fields: [{ name: 'qestado_1', precode: '1', value: '2', label: nil }] }
        ]
      )
    end
  end

  describe '#answer_label' do
    # Caso real: "fichaestado" (variable Hidden CUSTOM de cada proyecto,
    # a diferencia de "status" que es de sistema) -- resuelve el texto real
    # de un precode puntual en vez de hardcodear un string.
    it 'resuelve el texto de una respuesta dado el nombre de variable y el precode' do
      expect(lookup.answer_label('fichaestado', '2')).to eq('completa')
      expect(lookup.answer_label('fichaestado', '1')).to eq('incompleta')
    end

    it 'es case-insensitive en el nombre de variable, igual que el resto de la clase' do
      expect(lookup.answer_label('FICHAESTADO', '2')).to eq('completa')
    end

    it 'devuelve nil si la variable no existe o el precode no tiene respuesta' do
      expect(lookup.answer_label('no_existe', '1')).to be_nil
      expect(lookup.answer_label('fichaestado', '99')).to be_nil
    end
  end

  describe '#answer_label_matching' do
    # Diego: "el criterio que importa es que el label sea completa (con
    # fallback en complete o en c), mas alla del valor del precode (que en
    # general pero no siempre es 2)" -- el worker usa esto para el campo de
    # estado de un loop, en vez de asumir cual precode es "completa".
    it 'encuentra el texto que coincide con alguno de los candidatos, sin importar el precode' do
      expect(lookup.answer_label_matching('fichaestado', %w[completa complete c])).to eq('completa')
    end

    it 'es case-insensitive tanto en el nombre de variable como en los candidatos' do
      expect(lookup.answer_label_matching('FICHAESTADO', %w[COMPLETA])).to eq('completa')
    end

    it 'devuelve nil si ninguna respuesta coincide con los candidatos' do
      expect(lookup.answer_label_matching('fichaestado', %w[finalizada terminada])).to be_nil
    end

    it 'devuelve nil si la variable no existe' do
      expect(lookup.answer_label_matching('no_existe', %w[completa])).to be_nil
    end
  end

  describe '#answer_options' do
    # Diego: "al tomar el cuestionario no trae las opciones de respuesta,
    # esto sería bastante útil para las single" -- una Multi ya muestra el
    # texto de su propia opcion en el "Atributo" de esa fila, no necesita
    # esto (por eso #answer_options esta restringido a Single).
    it 'devuelve [precode, texto] de todas las respuestas de una Single' do
      expect(lookup.answer_options('fichaestado')).to eq(
        [['1', 'incompleta'], ['2', 'completa'], ['3', 'invalida']]
      )
    end

    it 'devuelve vacio para una Multi (las respuestas ya se ven en el Atributo de cada sub-respuesta)' do
      expect(lookup.answer_options('f4')).to eq([])
    end

    it 'devuelve vacio si la variable no existe' do
      expect(lookup.answer_options('no_existe')).to eq([])
    end
  end
end
