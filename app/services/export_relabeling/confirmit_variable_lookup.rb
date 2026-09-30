# frozen_string_literal: true

require 'nokogiri'

# Busca el {code, attribute, question} de una variable directo en el
# SurveySchema real (GetQuestionnaire), en vez de parsear el label ya
# compuesto (y potencialmente corrompido por el motor de export) que trae
# el .sps/.xlsx -- ver ExportRelabeling::LabelParser, que ahora queda como
# fallback para lo que esto no pueda resolver.
#
# Validado contra un schema real (p573989981944, GetQuestionnaire vivo):
# - Una pregunta "standalone" (Single/Open) trae su codigo y su pregunta ya
#   separados y limpios en <FormText><Title>/<Text>, sin el patron
#   "codigo - pregunta" que arma el EXPORT (ese patron lo genera la opcion
#   de export "Title and Text", no existe en el schema de origen).
# - Las columnas "f4_1", "p2_1", etc. NO son variables propias del schema
#   -- son la opcion de respuesta (Precode) de una variable padre Multi o
#   Grid ("f4", "p2"). Se resuelve separando el sufijo numerico/otro y
#   buscando la respuesta con ese Precode dentro del padre.
# - El texto (Title/Text/respuestas) puede traer HTML real adentro (ej.
#   "termo1", un bloque de consentimiento con <p>/<strong>/<span>) -- se
#   limpia con Nokogiri::HTML.fragment antes de devolverlo.
#
# Las respuestas de un Multi/Grid pueden venir inline (<Answer
# Precode="...">) o como referencia a una lista compartida (<Predefined
# ListSource="X" />, resuelta contra <PredefinedList EntityId="X"> en otra
# parte del mismo documento) -- confirmado con "qfichas" (precodes reales
# 'a'/'b'/'c'). Esa PredefinedList a veces trae su propio SourceEntityUrn
# apuntando a OTRO proyecto (rastro de que se copio de ahi alguna vez) --
# confirmado que el contenido real siempre esta duplicado localmente, ese
# atributo nunca hace falta seguirlo.
#
# El anidamiento puede tener MAS de un nivel: una PredefinedList puede
# a su vez tener su propio <Predefined ListSource="Y"> adentro en vez de
# (o ademas de) respuestas inline -- confirmado con "f9" (lista "list_s91":
# trae inline el precode 99 "Outros", pero reenvia a otra PredefinedList
# para los precodes 1-4). find_answer sigue la cadena recursivamente.
#
# Un nombre con sufijo "_other" (ej. "f9_99_other") es el texto abierto de
# "especificar" de esa MISMA opcion -- no es una respuesta nueva, resuelve
# a la misma entrada que su opcion base ("f9_99").
#
# Un Grid3D es un tercer patron de sub-respuesta, distinto a Multi/Grid:
# esta armado como "filas" (preguntas Multi anidadas dentro del Grid3D, ej.
# "f18x1", con su propio MultiAnswers siempre VACIO) por "columnas"
# (definidas una sola vez en el <Grid3DAnswers> del Grid3D contenedor, no
# en cada fila) -- confirmado con "f18x1_1".."f18x3_5". Ahi hay que subir
# al ancestro Grid3D en vez de bajar como en el resto de los casos.
#
# Pero el precode "otros/especifique" de un Grid3D no cuelga de una fila --
# vive directo en el <Grid3DAnswers> del Grid3D mismo (confirmado con
# "gf17s_98_other"/"gf17r_98_other": el sufijo "_other" resuelve a
# "gf17s_98", cuyo "padre" encontrado por nombre YA ES el propio Grid3D, no
# una fila anidada). Ahi no hay ancestro Grid3D que subir a buscar -- el
# nodo encontrado ya es ese Grid3D.
#
# Variables NO encontradas (ni directo, ni como sub-respuesta) devuelven
# nil -- pasa con variables de sistema sin autor (responseid, status). El
# llamador debe caer a LabelParser en ese caso.
#
# *** Depende de que la Rule/Data Template use "Title and Text" (u otra
# opcion que preserve el "nombre_variable : " como prefijo del header) --
# confirmado con el usuario que es la configuracion actual. Si el Data
# Template cambia de opcion y deja de incluir ese prefijo, este lookup
# pierde la forma de conectar la columna con el schema. ***
module ExportRelabeling
  class ConfirmitVariableLookup
    LANGUAGE = '1046'
    ANSWER_CONTAINERS = {
      'Multi' => { container: 'MultiAnswers', answer_tag: 'Answer' },
      'Grid' => { container: 'GridAnswers', answer_tag: 'GridAnswer' }
    }.freeze
    # Mapping separado del de arriba (ANSWER_CONTAINERS) a proposito -- este
    # se usa solo para #answer_label (resolver el TEXTO de un precode dado
    # nombre+precode, ver comentario de #quotas), no para el resto de la
    # clase (que resuelve columnas del export tipo "variable_precode"). Si
    # se agregara 'Single' al mapping compartido cambiaria tambien el
    # comportamiento de #call para cualquier columna "algo_N" cuyo "algo"
    # sea un Single -- caso no validado, se evita tocando ese mapping.
    DIRECT_ANSWER_CONTAINERS = ANSWER_CONTAINERS.merge(
      'Single' => { container: 'SingleAnswers', answer_tag: 'Answer' }
    ).freeze
    SUB_ANSWER_NAME = /\A(.+)_([a-zA-Z0-9]+)\z/.freeze
    OTHER_SUFFIX = /\A(.+)_other\z/i.freeze
    PREDEFINED_ANSWER_TAG = 'Answer'

    def self.call(schema_xml, variable_name)
      new(schema_xml).call(variable_name)
    end

    def initialize(schema_xml)
      # El "inner" que devuelve ConfirmitSoapClient#get_raw_survey_schema no
      # es XML valido por si solo -- son varios elementos raiz hermanos
      # (ReadFilter, Root, State, SchemaSource), sin un unico nodo raiz.
      # Se envuelve en uno sintetico antes de parsear; no afecta las
      # busquedas via "//" (buscan en todo el arbol sin importar el nivel).
      @doc = Nokogiri::XML("<root>#{schema_xml}</root>")
      @doc.remove_namespaces!
    end

    # Se normaliza a minuscula acá -- el schema siempre guarda los nombres
    # en minuscula, pero el .sps los trae en MAYUSCULA (a diferencia del
    # Excel, que ya vienen en minuscula) -- confirmado contra un proyecto
    # real (p573989981944, "F4_1" en el .sps vs "f4" en el schema).
    def call(variable_name)
      name = variable_name.to_s.downcase
      standalone_entry(name) || sub_answer_entry(name) || other_specify_entry(name)
    end

    # Cuotas del proyecto (progreso de campo) -- ver
    # ExportRelabeling::QuotaProgressBuilder para como se usa esto. Cada
    # <Quota> tiene 1+ <QuotaLimit> ("celda"): una meta (<Limit>) y 0+
    # <QuotaField> (nombre de variable EXPORTADA + precode que debe
    # cumplir). Confirmado contra 2 proyectos reales (p573989981944,
    # p314244165357) que <QuotaField><Name> siempre coincide con el nombre
    # de columna tal cual sale en el export -- mismo formato que ya
    # matcheamos en el resto de la clase, sin resolucion extra.
    #
    # El <Value> de un QuotaField a veces coincide con el <Precode> (caso
    # simple, ej. "llegoafin" Value=1) y a veces no (caso de una
    # sub-respuesta de Multi, ej. "qestado_1" Precode=1 pero Value=1..4) --
    # se devuelven los dos tal cual vienen, sin asumir cual es el que
    # importa para matchear contra los datos exportados (eso lo decide el
    # llamador).
    #
    # *** El <Value> del QuotaField es el PRECODE, pero la COLUMNA
    # exportada no siempre trae el precode -- confirmado contra un export
    # real (p314244165357) que el Data Template de ese proyecto exporta el
    # TEXTO de la respuesta ("MSD", "Região Sudeste"), no el numero
    # ("1", "2"). Por eso cada field trae ademas `label:`, el texto
    # resuelto para ese precode via el mismo mecanismo recursivo que ya
    # usa el resto de la clase (Predefined/PredefinedList incluido, ej.
    # "hidden_s132" -> lista externa) -- el llamador compara contra
    # `label || value`, priorizando el texto cuando se pudo resolver. ***
    def quotas
      @doc.xpath('//Quota').map do |quota_node|
        {
          name: quota_node.at_xpath('./Name')&.text,
          cells: quota_node.xpath('.//QuotaLimit').map { |limit_node| quota_cell(limit_node) }
        }
      end
    end

    # Resuelve el texto de la respuesta para (nombre de variable, precode)
    # -- reusa el mismo find_answer recursivo que el resto de la clase
    # (Predefined/PredefinedList incluido). A diferencia de #call, esto
    # busca directo por el nombre BASE de la variable (sin separar
    # sufijo "_N"), porque las cuotas simples (llegoafin, s0, hidden_s132)
    # SON el nombre base -- no hace falta (ni corresponde) el parseo de
    # sub-respuesta que usa #call para columnas tipo "f4_1".
    #
    # Publico (no solo usado internamente por #quotas) -- ver tambien
    # #answer_label_matching, que el worker usa para resolver el campo de
    # estado de un loop (ej. "fichaestado"), un caso donde no conviene
    # asumir el precode (ver ese comentario).
    def answer_label(variable_name, precode)
      return nil if variable_name.blank? || precode.blank?

      node = find_question_node(variable_name.to_s.downcase)
      return nil unless node

      config = DIRECT_ANSWER_CONTAINERS[node.name]
      return nil unless config

      container_node = node.at_xpath(".//#{config[:container]}")
      return nil unless container_node

      answer_node = find_answer(container_node, config[:answer_tag], precode)
      return nil unless answer_node

      clean_text(answer_text_of(answer_node))
    end

    # Encuentra el texto de respuesta que coincide (sin importar mayus/
    # minus) con alguno de los candidatos, SIN asumir cual precode es --
    # a diferencia de #answer_label. Diego: "el criterio que importa es
    # que el label sea completa (con fallback en complete o en c), mas
    # alla del valor del precode (que en general pero no siempre es 2)".
    # Caso real: el worker usa esto para resolver que texto de
    # "fichaestado" (variable Hidden CUSTOM de cada proyecto) representa
    # una ficha completa, sin hardcodear ni el string ni el numero de
    # precode.
    def answer_label_matching(variable_name, candidates)
      answer_labels(variable_name).find { |text| candidates.any? { |candidate| text.casecmp?(candidate) } }
    end

    # Opciones de respuesta (precode + texto) de una pregunta Single --
    # util para el "Diccionario" (ver RelabelExcelExportWorker), que hoy no
    # tiene forma de mostrar que valores puede tomar una Single (a
    # diferencia de una sub-respuesta de Multi/Grid, que ya trae su propio
    # texto en el "Atributo" de esa misma fila). Restringido a Single a
    # proposito -- Diego: "esto seria util para las single (las multiples
    # son binarias)", una Multi ya muestra el texto de cada opcion en su
    # propia fila del diccionario, no hace falta repetirlo aca.
    def answer_options(variable_name)
      return [] if variable_name.blank?

      node = find_question_node(variable_name.to_s.downcase)
      return [] unless node && node.name == 'Single'

      config = DIRECT_ANSWER_CONTAINERS[node.name]
      return [] unless config

      container_node = node.at_xpath(".//#{config[:container]}")
      return [] unless container_node

      collect_answer_options(container_node, config[:answer_tag])
    end

    # Tipo de nodo del schema para una variable de cuota (Single/Grid/Multi/
    # etc.) -- usado por RelabelExcelExportWorker para excluir las cuotas de
    # tipo Grid del proceso automatico (ver #quotas): el conteo interno de
    # Confirmit para variables de Grid/fichas no es confiable desde el
    # export (ver comentario de la clase QuotaProgressBuilder). Devuelve nil
    # si la variable no se encuentra en el schema.
    #
    # Un <QuotaField><Name> de una variable de Grid/fichas viene con el
    # nombre COMPUESTO tal cual sale en el export (ej. "qregion_1",
    # "distribucion_A"), no el nombre base del Grid ("qregion") -- ese
    # nombre compuesto no es una entidad real del schema (ver comentario de
    # la clase). Buscarlo directo con find_question_node no devuelve nil:
    # coincide por casualidad con el <Name> de ESE MISMO QuotaField dentro
    # de la propia definicion de la Quota (confirmado con un caso real,
    # p314244165357: hay literalmente un nodo <QuotaField><Name>qregion_1
    # </Name></QuotaField>, y como "QuotaField" no esta en QUESTION_TAGS,
    # find_question_node cae al primer match sin filtrar, devolviendo ESE
    # nodo). Por eso aca se exige que el nodo encontrado sea alguno de los
    # QUESTION_TAGS antes de aceptarlo -- si no, se reintenta con el nombre
    # base (mismo patron que #sub_answer_entry).
    def variable_type(variable_name)
      return nil if variable_name.blank?

      name = variable_name.to_s.downcase
      question_node_type(name) || sub_answer_variable_type(name)
    end

    private

    def question_node_type(name)
      node = find_question_node(name)
      return nil unless node && QUESTION_TAGS.include?(node.name)

      node.name
    end

    def sub_answer_variable_type(name)
      match = SUB_ANSWER_NAME.match(name)
      return nil unless match

      question_node_type(match[1])
    end

    def answer_labels(variable_name)
      return [] if variable_name.blank?

      node = find_question_node(variable_name.to_s.downcase)
      return [] unless node

      config = DIRECT_ANSWER_CONTAINERS[node.name]
      return [] unless config

      container_node = node.at_xpath(".//#{config[:container]}")
      return [] unless container_node

      collect_answer_options(container_node, config[:answer_tag]).map { |_precode, text| text }
    end

    # Recursivo, mismo criterio que find_answer (una PredefinedList puede
    # reenviar a otra en vez de tener respuestas propias) -- pero en vez de
    # buscar UN precode puntual, junta [precode, texto] de TODAS las
    # respuestas. Compartido entre #answer_options y #answer_labels (que
    # solo necesita el texto, no el precode).
    def collect_answer_options(container_node, answer_tag)
      options = container_node.xpath("./#{answer_tag}").map do |answer_node|
        text = clean_text(answer_text_of(answer_node))
        [answer_node['Precode'], text] if text
      end.compact

      predefined = container_node.at_xpath('./Predefined')
      return options unless predefined

      list_id = predefined['ListSource']
      referenced_answers = @doc.at_xpath("//PredefinedList[@EntityId='#{list_id}']/PredefinedListAnswers")
      return options unless referenced_answers

      options + collect_answer_options(referenced_answers, PREDEFINED_ANSWER_TAG)
    end

    def quota_cell(limit_node)
      {
        limit: limit_node.at_xpath('./Limit')&.text.to_i,
        fields: limit_node.xpath('.//QuotaField').map { |field_node| quota_field(field_node) }
      }
    end

    def quota_field(field_node)
      name = field_node.at_xpath('./Name')&.text
      precode = field_node.at_xpath('./Precode')&.text
      value = field_node.at_xpath('./Value')&.text

      { name: name, precode: precode, value: value, label: answer_label(name, precode || value) }
    end

    def other_specify_entry(name)
      match = OTHER_SUFFIX.match(name)
      return nil unless match

      call(match[1])
    end

    def standalone_entry(variable_name)
      node = find_question_node(variable_name)
      return nil unless node

      { code: clean_text(title_of(node)), attribute: nil, question: clean_text(text_of(node)) }
    end

    def sub_answer_entry(variable_name)
      match = SUB_ANSWER_NAME.match(variable_name)
      return nil unless match

      parent_name, precode = match[1], match[2]
      parent_node = find_question_node(parent_name)
      return nil unless parent_node

      own_answer_entry(parent_node, precode) || grid3d_answer_entry(parent_node, precode)
    end

    def own_answer_entry(parent_node, precode)
      config = ANSWER_CONTAINERS[parent_node.name]
      return nil unless config

      container_node = parent_node.at_xpath(".//#{config[:container]}")
      return nil unless container_node

      answer_node = find_answer(container_node, config[:answer_tag], precode)
      return nil unless answer_node

      {
        code: clean_text(title_of(parent_node)),
        attribute: clean_text(answer_text_of(answer_node)),
        question: clean_text(text_of(parent_node))
      }
    end

    # Un Grid3D esta armado como "filas" (preguntas Multi anidadas, ej.
    # "f18x1", con su MultiAnswers propio siempre VACIO) x "columnas"
    # (definidas una sola vez en el <Grid3DAnswers> del Grid3D contenedor,
    # no en cada fila) -- confirmado con "f18x1_1".."f18x3_5". Por eso hay
    # que subir al ancestro en vez de bajar como en el resto de los casos.
    def grid3d_answer_entry(parent_node, precode)
      grid3d = parent_node.name == 'Grid3D' ? parent_node : parent_node.ancestors('Grid3D').first
      return nil unless grid3d

      answer_node = grid3d.at_xpath("./Grid3DAnswers/Answer[@Precode='#{precode}']")
      return nil unless answer_node

      {
        code: clean_text(title_of(parent_node)) || clean_text(title_of(grid3d)),
        attribute: clean_text(answer_text_of(answer_node)),
        question: clean_text(text_of(parent_node))
      }
    end

    # Recursivo: una PredefinedList puede reenviar a otra en vez de (o
    # ademas de) tener respuestas propias -- ver comentario de la clase
    # (caso real "f9"/"list_s91", 2 niveles). El tag de respuesta cambia a
    # "Answer" apenas se entra a una PredefinedListAnswers, sin importar si
    # el nivel anterior era Multi o Grid -- confirmado que las listas
    # compartidas siempre usan ese tag, no "GridAnswer".
    def find_answer(container_node, answer_tag, precode)
      direct = container_node.at_xpath("./#{answer_tag}[@Precode='#{precode}']")
      return direct if direct

      predefined = container_node.at_xpath('./Predefined')
      return nil unless predefined

      list_id = predefined['ListSource']
      referenced_answers = @doc.at_xpath("//PredefinedList[@EntityId='#{list_id}']/PredefinedListAnswers")
      return nil unless referenced_answers

      find_answer(referenced_answers, PREDEFINED_ANSWER_TAG, precode)
    end

    UPPER = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    LOWER = 'abcdefghijklmnopqrstuvwxyz'

    # La mayoria de los nombres ya vienen en minuscula en el schema, pero no
    # es una garantia absoluta -- confirmado con "LinkFarmaco" (variable
    # Hidden armada a mano por scripting, EntityId="20069"), guardada con
    # mayusculas en el propio <Name>. Se compara sin importar el casing en
    # vez de asumir minuscula de un lado y mayuscula del otro.
    #
    # El mismo nombre puede repetirse en mas de un nodo del schema -- un
    # <Folder>/<Condition>/<QuotaField> de logica de ramificacion puede
    # coincidir exactamente con el nombre de la pregunta real (confirmado
    # con "farmacovigilancia": hay un <Folder> Y un <Single> con ese mismo
    # <Name>, y el Folder aparece PRIMERO en el documento -- tomar el
    # primer match a ciegas devolvia el Folder, sin FormTexts reales,
    # perdiendo silenciosamente el texto de la pregunta real). Se prioriza
    # el nodo cuyo tipo puede efectivamente tener una pregunta (los mismos
    # tags documentados arriba); si ninguno matchea ese criterio, se cae al
    # primer nodo encontrado (mismo comportamiento que antes).
    QUESTION_TAGS = %w[Single Multi Grid Grid3D Open Quota].freeze

    def find_question_node(variable_name)
      name_nodes = @doc.xpath("//Name[translate(text(), '#{UPPER}', '#{LOWER}')='#{variable_name}']")
      return nil if name_nodes.empty?

      preferred = name_nodes.find { |name_node| QUESTION_TAGS.include?(name_node.parent.name) }
      (preferred || name_nodes.first).parent
    end

    def title_of(node)
      node.at_xpath(".//FormTexts/FormText[@Language='#{LANGUAGE}']/Title")&.text
    end

    def text_of(node)
      node.at_xpath(".//FormTexts/FormText[@Language='#{LANGUAGE}']/Text")&.text
    end

    def answer_text_of(answer_node)
      answer_node.at_xpath(".//Texts/Text[@Language='#{LANGUAGE}']")&.text
    end

    # El Title/Text puede traer HTML real (ej. "termo1": <p>...<strong>...
    # </strong>...</p>) -- se limpia a texto plano. Un Title "roto"/vacio
    # (confirmado que pasa con textos de consentimiento sin codigo real,
    # ej. termo1) devuelve nil en vez de un string vacio o basura.
    def clean_text(raw)
      return nil if raw.nil?

      plain = Nokogiri::HTML.fragment(raw).text.strip
      plain.presence
    end
  end
end
