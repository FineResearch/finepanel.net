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
    # Formato "fila | columna | titulo. enunciado del Grid3D".
    expect(lookup.call('f18x1_1')).to eq(
      code: 'F18',
      attribute: 'Não realizaram esse teste | 1ª linha de tratamento',
      question: 'Titulo del Grid3D, no se usa para las filas'
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

  describe '#column_profile' do
    # Forma real confirmada contra p314244165357/p573989981944: Open numerico
    # = Numeric="true", fecha = IsDate="true", puntos de una escala = <Scale>
    # dentro de <Scales> de un Grid.
    let(:profile_lookup) do
      described_class.new(<<~XML)
        <Open EntityId="1" Numeric="true"><Name>i2</Name><FormTexts><FormText Language="1046"><Title>I2</Title><Text>Quanto tempo?</Text></FormText></FormTexts></Open>
        <Open EntityId="2" IsDate="true"><Name>data</Name><FormTexts><FormText Language="1046"><Title>Data</Title></FormText></FormTexts></Open>
        <Open EntityId="3"><Name>comentario</Name><FormTexts><FormText Language="1046"><Title>C1</Title></FormText></FormTexts></Open>
        <Single EntityId="4"><Name>f0</Name><FormTexts><FormText Language="1046"><Title>F0</Title><Text>Estado?</Text></FormText></FormTexts>
          <SingleAnswers><Answer Precode="1"><Texts><Text Language="1046">Rio de Janeiro</Text></Texts></Answer><Answer Precode="2"><Texts><Text Language="1046">S&#227;o Paulo</Text></Texts></Answer></SingleAnswers>
        </Single>
        <Multi EntityId="5"><Name>i3</Name><FormTexts><FormText Language="1046"><Title>I3</Title><Text>Sintomas?</Text></FormText></FormTexts>
          <MultiAnswers><Answer Precode="1"><Texts><Text Language="1046">Cansa&#231;o</Text></Texts></Answer><Answer Precode="99"><Texts><Text Language="1046">Outros</Text></Texts></Answer></MultiAnswers>
        </Multi>
        <Grid EntityId="6"><Name>p1</Name><FormTexts><FormText Language="1046"><Title>P1</Title><Text>Objetivos?</Text></FormText></FormTexts>
          <GridAnswers><GridAnswer Precode="1"><Texts><Text Language="1046">Reducao</Text></Texts></GridAnswer></GridAnswers>
          <Scales>
            <Scale Precode="1"><Texts><Text Language="1046">Nada importante</Text></Texts></Scale>
            <Scale Precode="2"><Texts><Text Language="1046">Pouco</Text></Texts></Scale>
            <Scale Precode="3"><Texts><Text Language="1046">Medio</Text></Texts></Scale>
          </Scales>
        </Grid>
      XML
    end

    it 'resuelve los puntos de una escala que viene como lista compartida (<Scales><Predefined/>)' do
      lookup = described_class.new(<<~XML)
        <Grid EntityId="6"><Name>s13</Name><FormTexts><FormText Language="1046"><Title>S13</Title><Text>Pensando em...</Text></FormText></FormTexts>
          <GridAnswers><GridAnswer Precode="1"><Texts><Text Language="1046">MSD</Text></Texts></GridAnswer></GridAnswers>
          <Scales><Predefined ListSource="17655" ReferencedEntityId="17655" /></Scales>
        </Grid>
        <PredefinedList EntityId="17655"><PredefinedListAnswers>
          <Answer Precode="1"><Texts><Text Language="1046">Nunca</Text></Texts></Answer>
          <Answer Precode="2"><Texts><Text Language="1046">As vezes</Text></Texts></Answer>
          <Answer Precode="3"><Texts><Text Language="1046">Sempre</Text></Texts></Answer>
        </PredefinedListAnswers></PredefinedList>
      XML

      expect(lookup.column_profile('s13_1')).to eq(
        type: :scale, scale_points: 3, options: [%w[1 Nunca], ['2', 'As vezes'], %w[3 Sempre]]
      )
    end

    it 'detecta una numerica por Numeric="true"' do
      expect(profile_lookup.column_profile('I2')).to eq(type: :numeric)
    end

    it 'detecta una fecha por IsDate="true"' do
      expect(profile_lookup.column_profile('data')).to eq(type: :date)
    end

    it 'trata un Open sin marcas como texto' do
      expect(profile_lookup.column_profile('comentario')).to eq(type: :text)
    end

    it 'devuelve las opciones de una Single' do
      expect(profile_lookup.column_profile('f0')).to eq(type: :single, options: [['1', 'Rio de Janeiro'], ['2', 'São Paulo']])
    end

    it 'detecta una sub-respuesta de Multi' do
      expect(profile_lookup.column_profile('I3_1')).to eq(type: :multi)
    end

    it 'detecta el texto abierto de "especificar" y lo vincula a su opcion' do
      expect(profile_lookup.column_profile('I3_99_OTHER')).to eq(type: :other_text, linked_to: 'I3_99')
    end

    it 'detecta una escala con su cantidad de puntos y las etiquetas de cada punto' do
      expect(profile_lookup.column_profile('P1_1')).to eq(
        type: :scale, scale_points: 3,
        options: [['1', 'Nada importante'], ['2', 'Pouco'], ['3', 'Medio']]
      )
    end

    it 'devuelve nil para una variable que no esta en el schema (sistema)' do
      expect(profile_lookup.column_profile('responseid')).to be_nil
    end
  end

  describe '#questionnaire_variables' do
    # Forma real de p314244165357/p573989981944: el cuestionario va entre el
    # Info "PRESENTATION" y el Single "iradatos1"; antes hay variables de
    # panel/sistema y despues cierre/control de duplicados.
    let(:flow_lookup) do
      described_class.new(<<~XML)
        <Single EntityId="1" VariableType="Panel"><Name>Pais1</Name><FormTexts><FormText Language="1046"><Title>Pais</Title></FormText></FormTexts></Single>
        <Info EntityId="2"><Name>PRESENTATION</Name></Info>
        <Single EntityId="3"><Name>f0</Name><FormTexts><FormText Language="1046"><Title>F0</Title></FormText></FormTexts></Single>
        <Multi EntityId="4"><Name>i3</Name><FormTexts><FormText Language="1046"><Title>I3</Title></FormText></FormTexts></Multi>
        <Open EntityId="5" VariableType="Hidden"><Name>oculta</Name></Open>
        <Folder EntityId="6"><Name>una carpeta</Name></Folder>
        <Grid3D EntityId="7"><Name>gf18</Name><FormTexts><FormText Language="1046"><Title>F18</Title></FormText></FormTexts>
          <Nodes><Multi EntityId="8"><Name>f18x1</Name></Multi><Multi EntityId="9"><Name>f18x2</Name></Multi></Nodes>
        </Grid3D>
        <Single EntityId="10"><Name>iradatos1</Name></Single>
        <Single EntityId="11"><Name>despues_del_cierre</Name></Single>
      XML
    end

    def units(lookup)
      lookup.questionnaire_variables(start_markers: %w[presentation presentacion], end_marker: 'iradatos1')
    end

    it 'devuelve solo las preguntas entre PRESENTATION e iradatos1, en orden del schema' do
      expect(units(flow_lookup).map { |unit| unit[:name] }).to eq(%w[f0 i3 gf18])
    end

    it 'excluye las Hidden, las anteriores a PRESENTATION y las posteriores a iradatos1' do
      names = units(flow_lookup).map { |unit| unit[:name] }

      expect(names).not_to include('oculta', 'Pais1', 'despues_del_cierre')
    end

    it 'trae el titulo de cada pregunta' do
      expect(units(flow_lookup).first).to include(name: 'f0', title: 'F0')
    end

    it 'una Grid3D es una sola unidad e incluye los nombres de sus filas anidadas' do
      grid = units(flow_lookup).find { |unit| unit[:name] == 'gf18' }

      expect(grid[:names]).to eq(%w[gf18 f18x1 f18x2])
    end

    it 'devuelve nil si falta algun marcador (no se puede acotar el cuestionario)' do
      sin_cierre = described_class.new('<Info EntityId="2"><Name>PRESENTATION</Name></Info><Single EntityId="3"><Name>f0</Name></Single>')
      sin_inicio = described_class.new('<Single EntityId="3"><Name>f0</Name></Single><Single EntityId="10"><Name>iradatos1</Name></Single>')

      expect(units(sin_cierre)).to be_nil
      expect(units(sin_inicio)).to be_nil
    end

    it 'acepta el marcador de inicio en espanol' do
      lookup = described_class.new('<Info EntityId="2"><Name>Presentacion</Name></Info><Single EntityId="3"><Name>f0</Name></Single><Single EntityId="10"><Name>iradatos1</Name></Single>')

      expect(units(lookup).map { |unit| unit[:name] }).to eq(%w[f0])
    end
  end

  # Confirmit marca con Numeric="true" a un Multi que pide un numero por opcion
  # (visto en p588393362171: F8/F9/F10, % de tiempo, cantidad de pacientes...).
  describe '#column_profile de un Multi numerico' do
    let(:numeric_multi_lookup) do
      described_class.new(<<~XML)
        <Multi EntityId="1" Numeric="true" OpenText="true" AutoSum="true"><Name>f8</Name>
          <FormTexts><FormText Language="1046"><Title>F8</Title><Text>Quantos pacientes?</Text></FormText></FormTexts>
          <MultiAnswers><Answer Precode="1"><Texts><Text Language="1046">Corticoides</Text></Texts></Answer></MultiAnswers>
        </Multi>
        <Multi EntityId="2"><Name>f11</Name>
          <FormTexts><FormText Language="1046"><Title>F11</Title></FormText></FormTexts>
          <MultiAnswers><Answer Precode="1"><Texts><Text Language="1046">Abbvie</Text></Texts></Answer></MultiAnswers>
        </Multi>
        <Grid3D EntityId="3"><Name>gf10</Name>
          <FormTexts><FormText Language="1046"><Title>F10</Title></FormText></FormTexts>
          <Nodes><Multi EntityId="4" Numeric="true"><Name>f10</Name><MultiAnswers /></Multi></Nodes>
          <Grid3DAnswers><Answer Precode="A"><Texts><Text Language="1046">1a linha</Text></Texts></Answer></Grid3DAnswers>
        </Grid3D>
      XML
    end

    it 'una opcion de un Multi con Numeric="true" es Multi Numeric, no una casilla 0/1' do
      expect(numeric_multi_lookup.column_profile('f8_1')).to eq(type: :multi_numeric)
    end

    it 'un Multi comun sigue siendo Multi' do
      expect(numeric_multi_lookup.column_profile('f11_1')).to eq(type: :multi)
    end

    it 'una fila numerica anidada en un Grid3D tambien es Multi Numeric (ej. f10_A)' do
      expect(numeric_multi_lookup.column_profile('f10_A')).to eq(type: :multi_numeric)
    end
  end

  # p588393362171: el .sps trae los nombres en MAYUSCULA y el lookup los baja a
  # minuscula ("f5_a"), pero el schema guarda el precode con letra en
  # mayuscula (Precode="A"). Sin resolverlos, el SPSS dejaba el label crudo de
  # Confirmit y el Dictionary sin Attribute (el Excel si lo tenia).
  describe '#call con precodes en letra y otro-especifique de una Single' do
    let(:letter_lookup) do
      described_class.new(<<~XML)
        <Multi EntityId="1" Numeric="true"><Name>f5</Name>
          <FormTexts><FormText Language="1046"><Title>F5</Title><Text>Total de pacientes</Text></FormText></FormTexts>
          <MultiAnswers><Answer Precode="A"><Texts><Text Language="1046">Psor&#237;ase</Text></Texts></Answer></MultiAnswers>
        </Multi>
        <Grid3D EntityId="3"><Name>gf10</Name>
          <FormTexts><FormText Language="1046"><Title>F10</Title></FormText></FormTexts>
          <Nodes><Multi EntityId="4" Numeric="true"><Name>f10</Name>
            <FormTexts><FormText Language="1046"><Title>F10</Title><Text>Pacientes tratados</Text></FormText></FormTexts>
            <MultiAnswers /></Multi></Nodes>
          <Grid3DAnswers><Answer Precode="A"><Texts><Text Language="1046">Recursos p&#250;blicos</Text></Texts></Answer></Grid3DAnswers>
        </Grid3D>
        <Single EntityId="5"><Name>f1</Name>
          <FormTexts><FormText Language="1046"><Title>F1</Title><Text>Qual a especialidade?</Text></FormText></FormTexts>
          <SingleAnswers>
            <Answer Precode="1"><Texts><Text Language="1046">Dermatologista</Text></Texts></Answer>
            <Answer Precode="99"><Texts><Text Language="1046">Outro. Especifique:</Text></Texts></Answer>
          </SingleAnswers>
        </Single>
      XML
    end

    it 'resuelve la opcion de un Multi con precode en letra aunque el nombre llegue en mayuscula o minuscula' do
      expected = { code: 'F5', attribute: 'Psoríase', question: 'Total de pacientes' }

      expect(letter_lookup.call('F5_A')).to eq(expected)
      expect(letter_lookup.call('f5_a')).to eq(expected)
    end

    it 'resuelve la columna de un Grid3D con precode en letra (ej. f10_A)' do
      expect(letter_lookup.call('F10_A')).to eq(code: 'F10', attribute: 'Recursos públicos', question: 'Pacientes tratados')
    end

    it 'resuelve el otro-especifique de una Single (f1_99_other) con el texto de la opcion como atributo' do
      expect(letter_lookup.call('F1_99_OTHER')).to eq(code: 'F1', attribute: 'Outro. Especifique:', question: 'Qual a especialidade?')
    end

    it 'un otro-especifique cuya opcion no existe en la Single sigue sin resolverse' do
      expect(letter_lookup.call('F1_77_OTHER')).to be_nil
    end
  end

  # p378408306422, bloque B1.1 ("lb11"): las columnas del Grid3D (los tratamientos) estan en
  # una lista compartida (<Predefined ListSource>) mas una opcion directa. Solo se resolvia
  # la directa y el Excel quedaba sin el tratamiento en el label.
  describe 'Grid3D con las columnas en una lista compartida' do
    let(:grid_lookup) do
      described_class.new(<<~XML)
        <Grid3D EntityId="1"><Name>lb11</Name>
          <FormTexts><FormText Language="1046"><Title>B1.1</Title><Text>Agora, gostariamos de saber quais atributos</Text></FormText></FormTexts>
          <Nodes>
            <Multi EntityId="2"><Name>lb11_1</Name><FormTexts><FormText Language="1046"><Text>Alta taxa de resposta</Text></FormText></FormTexts><MultiAnswers /></Multi>
            <Multi EntityId="3"><Name>lb11_2</Name><FormTexts><FormText Language="1046"><Text>Longa duracao</Text></FormText></FormTexts><MultiAnswers /></Multi>
          </Nodes>
          <Grid3DAnswers><Predefined ListSource="9" /><Answer Precode="19"><Texts><Text Language="1046">Nenhum dos tratamentos</Text></Texts></Answer></Grid3DAnswers>
        </Grid3D>
        <PredefinedList EntityId="9"><PredefinedListAnswers>
          <Answer Precode="1"><Texts><Text Language="1046">FOLFOX</Text></Texts></Answer>
          <Answer Precode="98"><Texts><Text Language="1046">Outro</Text></Texts></Answer>
        </PredefinedListAnswers></PredefinedList>
      XML
    end

    it 'sigue la lista compartida y arma "fila | columna" + "TITULO. enunciado del Grid3D"' do
      expect(grid_lookup.call('lb11_1_1')).to eq(
        code: 'B1.1', attribute: 'Alta taxa de resposta | FOLFOX', question: 'Agora, gostariamos de saber quais atributos'
      )
      expect(grid_lookup.call('LB11_2_98')[:attribute]).to eq('Longa duracao | Outro')
    end

    it 'sigue resolviendo la columna directa del Grid3D' do
      expect(grid_lookup.call('lb11_1_19')[:attribute]).to eq('Alta taxa de resposta | Nenhum dos tratamentos')
    end

    it 'una columna que no esta en la lista ni directa no se resuelve' do
      expect(grid_lookup.call('lb11_1_50')).to be_nil
    end
  end

  # p378408306422: a3a ("CONHECE") y a4a ("PRESCREVE") salian con labels identicos porque el
  # enunciado real vive en un <Info> anterior ("A3", "A4") y la pregunta repite un texto corto.
  describe 'enunciado del <Info> que precede a la pregunta' do
    let(:info_lookup) do
      described_class.new(<<~XML)
        <Info EntityId="1"><Name>a3</Name><FormTexts><FormText Language="1046"><Title>A3</Title><Text>Selecione os regimes que CONHECE:</Text></FormText></FormTexts></Info>
        <Multi EntityId="2"><Name>a3a</Name><FormTexts><FormText Language="1046"><Title>A3 - 1a Linha</Title><Text>CANCER em 1a Linha</Text></FormText></FormTexts>
          <MultiAnswers><Answer Precode="1"><Texts><Text Language="1046">FOLFOX</Text></Texts></Answer></MultiAnswers></Multi>
        <Multi EntityId="3"><Name>a3b</Name><FormTexts><FormText Language="1046"><Title>A3 - 2a Linha</Title><Text>CANCER em 2a Linha</Text></FormText></FormTexts>
          <MultiAnswers><Answer Precode="1"><Texts><Text Language="1046">FOLFOX</Text></Texts></Answer></MultiAnswers></Multi>
        <Info EntityId="4"><Name>a4</Name><FormTexts><FormText Language="1046"><Title>A4</Title><Text>E quais o Dr. PRESCREVE</Text></FormText></FormTexts></Info>
        <Multi EntityId="5"><Name>a4a</Name><FormTexts><FormText Language="1046"><Title>A4 - 1a Linha</Title><Text>CANCER em 1a Linha</Text></FormText></FormTexts>
          <MultiAnswers><Answer Precode="1"><Texts><Text Language="1046">FOLFOX</Text></Texts></Answer></MultiAnswers></Multi>
        <Info EntityId="6"><Name>nota</Name><FormTexts><FormText Language="1046"><Title>Nota</Title><Text>Texto suelto</Text></FormText></FormTexts></Info>
        <Single EntityId="7"><Name>p1</Name><FormTexts><FormText Language="1046"><Title>P1</Title><Text>Pergunta comum</Text></FormText></FormTexts></Single>
      XML
    end

    it 'antepone el enunciado del Info cuyo titulo es el codigo de la pregunta, asi a3a y a4a dejan de ser identicas' do
      expect(info_lookup.call('a3a_1')[:question]).to eq('Selecione os regimes que CONHECE: CANCER em 1a Linha')
      expect(info_lookup.call('a4a_1')[:question]).to eq('E quais o Dr. PRESCREVE - CANCER em 1a Linha')
    end

    it 'tambien alcanza a una pregunta que no esta pegada al Info (a3b, con a3a en el medio)' do
      expect(info_lookup.call('a3b_1')[:question]).to eq('Selecione os regimes que CONHECE: CANCER em 2a Linha')
    end

    it 'no toca una pregunta cuyo titulo no empieza con el codigo del Info (aunque haya un Info antes)' do
      expect(info_lookup.call('p1')[:question]).to eq('Pergunta comum')
    end
  end

  describe 'CSS/JavaScript pegado en el texto de una pregunta' do
    let(:code_lookup) do
      described_class.new(<<~XML)
        <Single EntityId="1"><Name>f8</Name><FormTexts><FormText Language="1046"><Title>F8</Title>
          <Text>Qual a porcentagem?&#10;&#10;(function(){&#10;var s=document.createElement('style');&#10;})();</Text></FormText></FormTexts></Single>
        <Single EntityId="2"><Name>s11</Name><FormTexts><FormText Language="1046"><Title>S11</Title>
          <Text>Destes pacientes, quantos:&#10;&#10;&#10;th#gs11_header0::after {&#10;  content: '';&#10;}</Text></FormText></FormTexts></Single>
      XML
    end

    it 'corta el JavaScript del final del texto' do
      expect(code_lookup.call('f8')[:question]).to eq('Qual a porcentagem?')
    end

    it 'corta el CSS del final del texto' do
      expect(code_lookup.call('s11')[:question]).to eq('Destes pacientes, quantos:')
    end
  end

  # Orden del cuestionario (ver ExportRelabeling::ColumnOrder).
  describe '#column_position' do
    let(:order_lookup) do
      described_class.new(<<~XML)
        <Folder EntityId="100"><Name>Background and Hidden</Name>
          <Nodes><Open EntityId="1"><Name>timesurvey</Name></Open></Nodes>
        </Folder>
        <Folder EntityId="101"><Name>questionnaire</Name>
          <Nodes>
            <Single EntityId="2"><Name>f0</Name>
              <SingleAnswers><Answer Precode="1"><Texts><Text Language="1046">Sim</Text></Texts></Answer><Answer Precode="99"><Texts><Text Language="1046">Outro</Text></Texts></Answer></SingleAnswers>
            </Single>
            <Multi EntityId="3"><Name>p5</Name>
              <MultiAnswers>
                <Answer Precode="1"><Texts><Text Language="1046">A</Text></Texts></Answer>
                <Answer Precode="9"><Texts><Text Language="1046">B</Text></Texts></Answer>
                <Answer Precode="10"><Texts><Text Language="1046">C</Text></Texts></Answer>
              </MultiAnswers>
            </Multi>
            <Grid3D EntityId="4"><Name>gs11</Name>
              <Nodes><Multi EntityId="5"><Name>s11a</Name><MultiAnswers /></Multi><Multi EntityId="6"><Name>s11b</Name><MultiAnswers /></Multi></Nodes>
              <Grid3DAnswers><Answer Precode="1" /><Answer Precode="2" /></Grid3DAnswers>
            </Grid3D>
            <Open EntityId="7"><Name>s11aa</Name></Open>
          </Nodes>
        </Folder>
      XML
    end

    it 'ordena por pregunta del cuestionario y despues por opcion (en el orden del schema, no el numerico)' do
      names = %w[f0 p5_1 p5_9 p5_10 s11a_1 s11a_2 s11b_1 s11b_2 s11aa]
      positions = names.map { |name| order_lookup.column_position(name) }

      expect(positions).to eq(positions.sort)
      expect(positions.map(&:first).uniq.length).to eq(5)
    end

    it 'las filas de un Grid3D usan las opciones del Grid3D (s11a_1, s11a_2, despues s11b_1...)' do
      expect(order_lookup.column_position('s11a_2') <=> order_lookup.column_position('s11b_1')).to eq(-1)
    end

    it 'el campo "other" va despues de TODAS las opciones de su pregunta, como lo exporta Confirmit' do
      expect(order_lookup.column_position('p5_9_other') <=> order_lookup.column_position('p5_10')).to eq(1)
      expect(order_lookup.column_position('p5_9_other') <=> order_lookup.column_position('s11a_1')).to eq(-1)
    end

    it 'las variables fuera de la carpeta "questionnaire" (sistema/ocultas) y las que no estan en el schema no tienen posicion' do
      expect(order_lookup.column_position('timesurvey')).to be_nil
      expect(order_lookup.column_position('responseid')).to be_nil
      expect(order_lookup.column_position('')).to be_nil
    end

    it 'un schema sin carpeta "questionnaire" no ordena nada' do
      plain = described_class.new('<Single EntityId="2"><Name>f0</Name></Single>')

      expect(plain.column_position('f0')).to be_nil
    end
  end

  # p803162949296 (FP-18810G), preguntas F6a/F7/F8: las filas anidadas de un Grid3D traen
  # una lista propia de respuestas (la de diagnosticos), pero las columnas exportadas
  # ("f6a1_2") son las respuestas del Grid3D (Leve/Moderada/Grave). Se usaba la lista de la fila
  # y F6A1_2 salia como "Espondilite Anquilosante | Artrite Psoriasica (^f('f6')['1']^ pacientes)".
  describe 'filas de un Grid3D que arrastran una lista propia de respuestas' do
    let(:nbsp) { " " }
    let(:rows_lookup) do
      described_class.new(<<~XML)
        <Grid3D EntityId="1"><Name>gf6a</Name>
          <FormTexts><FormText Language="1046"><Title>F6a</Title><Text>Considerando os seus pacientes, como os distribuiria entre as severidades?</Text></FormText></FormTexts>
          <Nodes>
            <Multi EntityId="2"><Name>f6a1</Name>
              <FormTexts><FormText Language="1046"><Title></Title><Text>Artrite Psori&#225;sica&#160;(^f('f6')['1']^ pacientes)</Text></FormText></FormTexts>
              <MultiAnswers><Predefined ListSource="9" /></MultiAnswers></Multi>
          </Nodes>
          <Grid3DAnswers>
            <Answer Precode="1"><Texts><Text Language="1046">Leve</Text></Texts></Answer>
            <Answer Precode="2"><Texts><Text Language="1046">Moderada</Text></Texts></Answer>
          </Grid3DAnswers>
        </Grid3D>
        <PredefinedList EntityId="9"><PredefinedListAnswers>
          <Answer Precode="1"><Texts><Text Language="1046">Artrite Psori&#225;sica</Text></Texts></Answer>
          <Answer Precode="2"><Texts><Text Language="1046">Espondilite Anquilosante</Text></Texts></Answer>
        </PredefinedListAnswers></PredefinedList>
        <Grid3D EntityId="3"><Name>gf7</Name>
          <FormTexts><FormText Language="1046"><Title>F7</Title><Text>Considerando os seus pacientes moderados a graves, como os distribuiria entre os setores?</Text></FormText></FormTexts>
          <Nodes>
            <Multi EntityId="4"><Name>f7x1</Name>
              <FormTexts><FormText Language="1046"><Title></Title><Text>Artrite Psori&#225;sica&#160;(^Sum(f('f6a1')['2'],f('f6a1')['3'])^ pacientes)</Text></FormText></FormTexts>
              <MultiAnswers><Predefined ListSource="9" /></MultiAnswers></Multi>
          </Nodes>
          <Grid3DAnswers><Answer Precode="1"><Texts><Text Language="1046">&lt;strong&gt;Setor privado&lt;/strong&gt;&lt;br /&gt;(custeado pelo convenio)</Text></Texts></Answer></Grid3DAnswers>
        </Grid3D>
        <Grid3D EntityId="5"><Name>gf8</Name>
          <FormTexts><FormText Language="1046"><Title>F8</Title><Text>Como distribuiria os seus pacientes entre os seguintes perfis:</Text></FormText></FormTexts>
          <Nodes>
            <Multi EntityId="6"><Name>f8x1</Name>
              <FormTexts><FormText Language="1046"><Title></Title><Text>Setor privado&#160;(^Sum(f('f7x1')['1'])^ pacientes)</Text></FormText></FormTexts>
              <MultiAnswers><Predefined ListSource="9" /></MultiAnswers></Multi>
          </Nodes>
          <Grid3DAnswers><Answer Precode="1"><Texts><Text Language="1046">Ainda nao receberam tratamento</Text></Texts></Answer></Grid3DAnswers>
        </Grid3D>
        <Grid3D EntityId="7"><Name>gf5</Name>
          <FormTexts><FormText Language="1046"><Title>F5</Title><Text>Dos seus pacientes, quantos tem as seguintes condicoes?</Text></FormText></FormTexts>
          <Nodes>
            <Multi EntityId="8"><Name>f5</Name>
              <FormTexts><FormText Language="1046"><Title>F5</Title><Text>Total de pacientes atendidos</Text></FormText></FormTexts>
              <MultiAnswers><Answer Precode="A"><Texts><Text Language="1046">Psor&#237;ase</Text></Texts></Answer></MultiAnswers></Multi>
          </Nodes>
        </Grid3D>
      XML
    end

    it 'toma la columna del Grid3D (no la lista de la fila): fila | columna | TITULO. enunciado, con la fila sin el piping del final' do
      expect(rows_lookup.call('F6A1_2')).to eq(
        code: 'F6a', attribute: 'Artrite Psoriásica | Moderada',
        question: 'Considerando os seus pacientes, como os distribuiria entre as severidades?'
      )
      expect(rows_lookup.call('F6A1_1')[:attribute]).to eq('Artrite Psoriásica | Leve')
    end

    it 'si el piping del final referencia a la fila de otro Grid3D que YA esta en el texto, no se repite' do
      expect(rows_lookup.call('F7X1_1')[:attribute]).to eq('Artrite Psoriásica | Setor privado(custeado pelo convenio)')
    end

    it 'si el piping referencia a la fila de otro Grid3D que NO esta en el texto, esa fila va de contexto (F8: diagnostico - setor)' do
      expect(rows_lookup.call('F8X1_1')).to eq(
        code: 'F8', attribute: 'Artrite Psoriásica - Setor privado | Ainda nao receberam tratamento',
        question: 'Como distribuiria os seus pacientes entre os seguintes perfis:'
      )
    end

    it 'un Grid3D que no declara esa columna sigue usando las respuestas propias de la fila (gf5)' do
      expect(rows_lookup.call('F5_A')[:attribute]).to eq('Psoríase')
    end

    # F5 y F7 de p588393362171: la fila repite las opciones del Grid3D. Esos labels ya se
    # entregaron y no tienen que cambiar por arreglar F6a/F7/F8.
    it 'si la lista de la fila y la columna del Grid3D dicen lo mismo, queda el formato de siempre (no cambia labels ya entregados)' do
      same_lists = described_class.new(<<~XML)
        <Grid3D EntityId="1"><Name>gf7b</Name>
          <FormTexts><FormText Language="1046"><Title>F7</Title><Text>Distribua os pacientes por severidade</Text></FormText></FormTexts>
          <Nodes>
            <Multi EntityId="2"><Name>f7b</Name>
              <FormTexts><FormText Language="1046"><Title>F7</Title><Text>Pacientes atendidos</Text></FormText></FormTexts>
              <MultiAnswers><Answer Precode="A"><Texts><Text Language="1046">Leve</Text></Texts></Answer></MultiAnswers></Multi>
          </Nodes>
          <Grid3DAnswers><Answer Precode="A"><Texts><Text Language="1046">Leve</Text></Texts></Answer></Grid3DAnswers>
        </Grid3D>
      XML

      expect(same_lists.call('F7B_A')).to eq(code: 'F7', attribute: 'Leve', question: 'Pacientes atendidos')
    end
  end
end
