# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'cgi'

module FinePanelSetup
  class ConfirmitSoapClient
    # Declarar xmlns:xsi/xmlns:xsd en el envelope, aunque un request puntual no
    # los use, evita un problema real que ya nos paso: el contenido que se lee
    # de GetQuestionnaire trae atributos "xsi:type=..." (ej. en ReadFilter), y
    # si se manda ese mismo contenido de vuelta en un Update sin declarar ese
    # namespace en el <soap:Envelope>, Confirmit devuelve un 500 generico sin
    # ningun detalle util -- no es un problema de permisos ni de la operacion
    # en si, es XML invalido de nuestro lado (mismo tipo de bug que el de la
    # clave con "&" sin escapar). Confirmado contra un proyecto real (2026-08-21).
    SOAP_ENVELOPE_NAMESPACES = 'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' \
                               'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
                               'xmlns:xsd="http://www.w3.org/2001/XMLSchema"'

    # El host correcto depende de en que servidor vive el proyecto, no es fijo por
    # "region del cliente": p774756690265 vive en el SaaS US, no en Horizons EU
    # (Forsta soporte, Sam, 2026-08-21). author.us.confirmit.com autenticaba bien
    # pero apuntaba a un servidor distinto al que aloja este proyecto especifico.
    LOGON_ENDPOINT = ENV.fetch(
      'CONFIRMIT_LOGON_ENDPOINT',
      'https://ws.us.confirmit.com/confirmit/webservices/current/logon.asmx'
    )

    def log_on
      username = ENV['CONFIRMIT_API_USERNAME']
      password = ENV['CONFIRMIT_API_PASSWORD']
      raise 'CONFIRMIT_API_USERNAME/CONFIRMIT_API_PASSWORD no configurados' if username.blank? || password.blank?

      envelope = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope #{SOAP_ENVELOPE_NAMESPACES}>
          <soap:Body>
            <LogOnUser xmlns="http://firmglobal.com/Confirmit/webservices/">
              <username>#{xml_escape(username)}</username>
              <password>#{xml_escape(password)}</password>
            </LogOnUser>
          </soap:Body>
        </soap:Envelope>
      XML

      response_body = post_soap(
        endpoint: LOGON_ENDPOINT,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/LogOnUser',
        envelope: envelope
      )

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!
      result = doc.at_xpath('//LogOnUserResult')
      fault = doc.at_xpath('//Fault')

      raise "Confirmit LogOnUser fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}" if fault
      raise 'Confirmit LogOnUser no devolvio una clave de autorizacion' if result.nil? || result.text.blank?

      result.text
    end

    # Namespace y forma del request/response confirmados contra el WSDL real (Forsta soporte, 2026-08-19):
    # https://horizons.confirmit.eu/confirmit/webservices/current/authoring.asmx?wsdl
    # Pero el host EU devolvia Internal Server Error para TODO (hasta llamadas de solo
    # lectura) porque el proyecto de prueba p774756690265 no vive ahi -- vive en el
    # SaaS US. Host correcto confirmado por Forsta soporte (Sam, 2026-08-21).
    AUTHORING_ENDPOINT = ENV.fetch(
      'CONFIRMIT_AUTHORING_ENDPOINT',
      'https://ws.us.confirmit.com/confirmit/webservices/current/authoring.asmx'
    )

    # Servicio no-deprecated para escribir (Update). Mismo host que Authoring,
    # mismo namespace, .asmx en minuscula. Confirmado por Forsta soporte
    # (Sam, 2026-08-21) como el reemplazo correcto de Authoring para GetQuestionnaire
    # + Update -- Authoring sigue funcionando para todo lo demas (DuplicateProject,
    # GetProjectInfo, etc.) porque SurveyDesign no tiene esas operaciones.
    SURVEY_DESIGN_ENDPOINT = ENV.fetch(
      'CONFIRMIT_SURVEY_DESIGN_ENDPOINT',
      'https://ws.us.confirmit.com/confirmit/webservices/current/surveydesign.asmx'
    )

    def duplicate_project(source_project_id:, new_project_name:)
      key = log_on

      envelope = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope #{SOAP_ENVELOPE_NAMESPACES}>
          <soap:Body>
            <DuplicateProject xmlns="http://firmglobal.com/Confirmit/webservices/">
              <key>#{xml_escape(key)}</key>
              <projectId>#{xml_escape(source_project_id)}</projectId>
              <newProjectName>#{xml_escape(new_project_name)}</newProjectName>
            </DuplicateProject>
          </soap:Body>
        </soap:Envelope>
      XML

      response_body = post_soap(
        endpoint: AUTHORING_ENDPOINT,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/DuplicateProject',
        envelope: envelope
      )

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!
      result = doc.at_xpath('//DuplicateProjectResult')
      fault = doc.at_xpath('//Fault')

      if fault
        { ok: false, error: fault.at_xpath('.//faultstring')&.text || fault.text }
      elsif result && result.text.present?
        { ok: true, project_id: result.text }
      else
        { ok: false, error: "Respuesta inesperada: #{response_body[0, 300]}" }
      end
    end

    # El nodo de script "definiciones" tiene dos partes: todo lo que esta antes de
    # este marcador es lo que arma el Generador de Script (A1-A10, especifico de
    # cada proyecto nuevo); todo lo que esta desde el marcador en adelante es
    # configuracion tecnica fija (clave, redirect, rutinas de BD) que hay que
    # preservar tal cual. Confirmado inspeccionando el proyecto real (2026-08-21).
    DEFINITIONS_SCRIPT_NAME = 'definiciones'
    DEFINITIONS_MARKER = '//FASE B - SETEOS NECESARIOS'
    PROJECT_KEY_FIELD_PATTERN = /f\("clave"\)\.set\("[^"]*"\)/

    # El bloque C4 ("SI NO VAN EN CLIENTLINKS...") vive DESPUES del marcador
    # FASE B -- o sea, en la parte que se preserva tal cual, no en la que
    # arma el Generador de Script. Trae un template fijo (Brasil=1, el resto
    # en 0, para un subconjunto de paises) que hay que pisar a mano por
    # proyecto -- si no se pisa, un proyecto duplicado siempre queda con esos
    # valores de ejemplo, no los del proyecto real (confirmado por el
    # usuario 2026-08-27: los primerid generados se estaban perdiendo porque
    # vivian en una seccion nueva separada que nunca tocaba este bloque, y
    # este bloque corria despues, pisando todo con los ceros del template).
    PRIMERID_BLOCK_MARKER = '//C4.'
    PRIMERID_BLOCK_END_MARKER = '//Otros paises'

    # Solo lectura: arma el ScriptCode final que habria que escribir en el nodo
    # "definiciones" del proyecto -- reemplaza la parte de antes del marcador por
    # el script recien generado, preserva intacta la parte de despues. Si se pasa
    # project_key, ademas reemplaza el valor actual de f("clave").set("...") por
    # el real (el placeholder que trae el proyecto duplicado, ej. "WUUBGRLO", no
    # sirve -- hay que pisarlo con el que devuelve fetch_project_key). Si se pasa
    # primerid_lines, ademas pisa el bloque de paises del C4 (ver arriba) con
    # las lineas dadas -- vacio/nil lo deja intacto (proyectos "Fine en
    # Confirmit" no usan C4, no hace falta tocarlo). No escribe nada en
    # Confirmit por si sola -- ver write_definitions_script.
    def build_definitions_script(project_id:, generated_script:, project_key: nil, primerid_lines: nil)
      key = log_on
      response_body = get_questionnaire(key: key, project_id: project_id, endpoint: AUTHORING_ENDPOINT)

      current_script_code = extract_definitions_script_code(response_body)
      marker_index = current_script_code.index(DEFINITIONS_MARKER)
      raise "No se encontro el marcador \"#{DEFINITIONS_MARKER}\" en el script \"#{DEFINITIONS_SCRIPT_NAME}\" del proyecto #{project_id}" unless marker_index

      preserved_tail = current_script_code[marker_index..-1]
      if project_key.present?
        preserved_tail = preserved_tail.sub(PROJECT_KEY_FIELD_PATTERN, "f(\"clave\").set(\"#{project_key}\")")
      end
      if primerid_lines.present?
        preserved_tail = replace_primerid_block(preserved_tail, primerid_lines)
      end

      "#{generated_script.to_s.strip}\n\n\n#{preserved_tail}"
    end

    # Escribe de verdad el ScriptCode final en el nodo "definiciones" del
    # proyecto, via el servicio SurveyDesign (no el Authoring deprecated -- ese
    # es el que Forsta documenta para Update, confirmado 2026-08-21). Ver
    # write_script_node para el detalle de como se arma el request.
    def write_definitions_script(project_id:, script_code:)
      write_script_node(project_id: project_id, script_name: DEFINITIONS_SCRIPT_NAME, new_script_code: script_code)
    end

    # No es una llamada SOAP -- es el link generico publico de la encuesta
    # (distinto host, survey.finepanel.net). Solo funciona si el proyecto ya
    # esta lanzado (SetSurveyStatus a Production con la base de datos creada).
    # La pagina muestra como texto "La clave del proyecto es XXXXXXXX", que hay
    # que copiar en el "f(\"clave\").set(...)" del script "definiciones".
    # Confirmado contra el proyecto de test real (2026-08-21).
    GENERIC_SURVEY_LINK = ENV.fetch('CONFIRMIT_GENERIC_SURVEY_LINK_HOST', 'https://survey.finepanel.net/wix')
    PROJECT_KEY_PATTERN = /La clave del proyecto es (\w+)/

    def fetch_project_key(project_id:)
      uri = URI.parse("#{GENERIC_SURVEY_LINK}/#{project_id}.aspx")
      response = Net::HTTP.get_response(uri)

      # el link generico redirige una vez (ej. a /wix/1/pXXXX.aspx) antes de mostrar la pagina
      if response.is_a?(Net::HTTPRedirection) && response['location'].present?
        uri = URI.parse(response['location'])
        response = Net::HTTP.get_response(uri)
      end

      raise "El link generico devolvio HTTP #{response.code} para el proyecto #{project_id}" unless response.is_a?(Net::HTTPSuccess)

      match = response.body.match(PROJECT_KEY_PATTERN)
      raise "No se encontro \"La clave del proyecto es ...\" en la respuesta -- verificar que el proyecto #{project_id} ya este lanzado (Production)" unless match

      match[1]
    end

    # Servicio distinto al de Authoring/SurveyDesign (mismo host, .asmx en
    # minuscula). Confirmado por Forsta soporte (Sam, 2026-08-21) con un request
    # real que funciono -- LaunchSurvey es asincronico, devuelve un TaskID que
    # hay que consultar con GetTaskStatus hasta que llegue a "Complete".
    DEPLOYER_ENDPOINT = ENV.fetch(
      'CONFIRMIT_DEPLOYER_ENDPOINT',
      'https://ws.us.confirmit.com/confirmit/webservices/current/surveydeployer.asmx'
    )

    # "Lanzar" el proyecto (crear la base de datos y ponerlo en Production).
    # Sin esto el link generico de la encuesta no muestra nada y SetSurveyStatus
    # falla porque la base "survey_pXXXXXXXXXX" todavia no existe. Devuelve el
    # TaskID -- usar wait_for_task para esperar a que termine antes de intentar
    # fetch_project_key.
    #
    # generate_wi_option default es "WiNet" (no "DontGenerate", que es lo que
    # aparece en el ejemplo de Forsta soporte): en un duplicado nuevo, si no se
    # genera el Web Interview el link generico da 404. "DontGenerate" solo
    # tiene sentido si el WI ya existia de un lanzamiento previo (confirmado
    # probando ambos casos contra un proyecto de test real, 2026-08-21).
    #
    # generate_db_option default es "Rebuild" (no "CreateNewDatabase" ni
    # "DontGenerate"). Confirmado por el usuario (2026-08-25): "Rebuild"
    # actualiza la estructura/version del proyecto SIN perder los datos ya
    # acumulados (a diferencia de "CreateNewDatabase", que crea una base de
    # cero) -- por eso es la opcion correcta tanto para un duplicado nuevo
    # (sin datos que perder) como para relanzar un proyecto existente en
    # produccion.
    #
    # key: opcional. IMPORTANTE -- confirmado con logs reales de tareas de
    # Confirmit (2026-08-25) en el proyecto de redirect Fine<->Forsta: si este
    # launch va justo despues de un Update (ej. append_fnp_assignment) hecho
    # con una sesion (key) DISTINTA -- es decir, cada llamada abriendo su
    # propio LogOnUser -- Confirmit a veces salta por completo los pasos de
    # regeneracion de base de datos ("Generating DB"/"Updating system
    # tables"/"Upgrading database"/"Saving project version"), aunque
    # generateDBOption sea "Rebuild" y el request este bien formado. Pasando
    # la MISMA key que se uso para el Update previo, el problema desaparece
    # (probado repetidamente). No se sabe por que Confirmit se comporta asi
    # -- parece un tema de sesiones/locking interno del lado del servidor,
    # no algo documentado -- pero el fix empirico es reusar la sesion.
    def launch_survey(project_id:, database_type: 'Production', generate_db_option: 'Rebuild', generate_wi_option: 'WiNet', key: nil)
      key ||= log_on

      envelope = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope #{SOAP_ENVELOPE_NAMESPACES}>
          <soap:Body>
            <LaunchSurvey xmlns="http://firmglobal.com/Confirmit/webservices/">
              <key>#{xml_escape(key)}</key>
              <projectId>#{xml_escape(project_id)}</projectId>
              <databaseType>#{xml_escape(database_type)}</databaseType>
              <generateDBOption>#{xml_escape(generate_db_option)}</generateDBOption>
              <generateWiOption>#{xml_escape(generate_wi_option)}</generateWiOption>
            </LaunchSurvey>
          </soap:Body>
        </soap:Envelope>
      XML

      response_body = post_soap(
        endpoint: DEPLOYER_ENDPOINT,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/LaunchSurvey',
        envelope: envelope
      )

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!
      fault = doc.at_xpath('//Fault')
      raise "Confirmit LaunchSurvey fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}" if fault

      result = doc.at_xpath('//LaunchSurveyResult')
      raise "Confirmit LaunchSurvey no devolvio un TaskID: #{response_body[0, 300]}" if result.nil? || result.text.blank?

      result.text.to_i
    end

    def get_task_status(task_id:)
      key = log_on

      envelope = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope #{SOAP_ENVELOPE_NAMESPACES}>
          <soap:Body>
            <GetTaskStatus xmlns="http://firmglobal.com/Confirmit/webservices/">
              <key>#{xml_escape(key)}</key>
              <taskId>#{task_id.to_i}</taskId>
            </GetTaskStatus>
          </soap:Body>
        </soap:Envelope>
      XML

      response_body = post_soap(
        endpoint: DEPLOYER_ENDPOINT,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/GetTaskStatus',
        envelope: envelope
      )

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!
      fault = doc.at_xpath('//Fault')
      raise "Confirmit GetTaskStatus fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}" if fault

      doc.at_xpath('//GetTaskStatusResult')&.text
    end

    # Espera (polling simple) a que un TaskID de SurveyDeployer termine.
    # timeout_seconds/poll_interval son bajos por defecto porque esto se usa en
    # un request HTTP sincronico del controller -- si tarda mas, hay que pasar
    # a un job en background en vez de subir estos valores.
    def wait_for_task(task_id:, timeout_seconds: 60, poll_interval: 3)
      deadline = Time.now + timeout_seconds

      loop do
        status = get_task_status(task_id: task_id)
        return status if %w[Complete Aborted Error].include?(status)
        raise "Timeout esperando el TaskID #{task_id} (ultimo estado: #{status})" if Time.now > deadline

        sleep(poll_interval)
      end
    end

    # Cada linea del A10 (bloque "COPIAR EN ASIGNACION DE INCENTIVOS") se agrega
    # al ultimo nodo de script dentro de esta carpeta del panel. Cuando ese nodo
    # se acerca a las ~400 lineas hay que crear uno nuevo a mano (por ahora) --
    # confirmado inspeccionando el panel real (2026-08-21). Los nodos por año no
    # son hijos directos de la carpeta: estan anidados dentro de un Condition
    # intermedio (junto con otras carpetas/alertas de mail que no son parte de
    # esta secuencia), asi que se identifican por prefijo de nombre, no por
    # posicion estructural -- el nombre exacto del ultimo cambia con el tiempo
    # ("Asignacion de incentivos <año>"), por eso se toma el ultimo por orden
    # de documento entre los que matchean el prefijo, no un nombre fijo.
    INCENTIVE_ASSIGNMENT_FOLDER = 'Asignacion de Incentivos por Proyecto'
    INCENTIVE_ASSIGNMENT_NODE_PREFIX = 'Asignacion de incentivos'
    INCENTIVE_ASSIGNMENT_LINE_LIMIT = 400
    INCENTIVE_ASSIGNMENT_WARN_THRESHOLD = 390

    # Solo lectura: identifica el ultimo nodo de script dentro de la carpeta de
    # asignacion de incentivos del panel y cuenta sus lineas, para saber si ya
    # esta cerca del limite y conviene crear un nodo nuevo. No escribe nada.
    def check_incentive_assignment_limit(project_id:)
      check_script_limit(
        project_id: project_id,
        folder_name: INCENTIVE_ASSIGNMENT_FOLDER,
        node_prefix: INCENTIVE_ASSIGNMENT_NODE_PREFIX,
        line_limit: INCENTIVE_ASSIGNMENT_LINE_LIMIT,
        warn_threshold: INCENTIVE_ASSIGNMENT_WARN_THRESHOLD
      )
    end

    # Solo aplica cuando la programacion NO es de Fine en Confirmit: el cliente
    # redirige a este proyecto (p1773348171), carpeta "asignacion de p en base
    # a Project", donde cada linea del ultimo nodo mapea el codigo de proyecto
    # de Fine ("FP-XXXXX") al codigo de proyecto de Forsta/el cliente ("pXXXX..."),
    # ej. if(f('Project')=="FP-18743G"){f("fnp").set("p533230485360");}. Limite
    # tecnico ~523 lineas por nodo (confirmado por el usuario) -- se avisa antes,
    # en 500, para crear el nodo nuevo con margen. Confirmado inspeccionando el
    # proyecto real (2026-08-22): responde bien tanto por Authoring como por
    # SurveyDesign (a diferencia del panel legacy de incentivos, que no
    # responde por SurveyDesign) -- este si se podria escribir automaticamente
    # mas adelante con el mismo mecanismo de write_script_node.
    FNP_ASSIGNMENT_PROJECT_ID = 'p1773348171'
    FNP_ASSIGNMENT_FOLDER = 'asignacion de p en base a Project'
    FNP_ASSIGNMENT_NODE_PREFIX = 'asigna numero p'
    FNP_ASSIGNMENT_LINE_LIMIT = 523
    FNP_ASSIGNMENT_WARN_THRESHOLD = 500

    # Solo lectura, mismo criterio que check_incentive_assignment_limit pero
    # para el mapeo Fine<->Forsta. project_id tiene default porque este mapeo
    # vive siempre en el mismo proyecto fijo (p1773348171), no en cada proyecto
    # nuevo -- se deja como parametro solo por si eso cambia en el futuro.
    def check_fnp_assignment_limit(project_id: FNP_ASSIGNMENT_PROJECT_ID, key: nil)
      check_script_limit(
        project_id: project_id,
        folder_name: FNP_ASSIGNMENT_FOLDER,
        node_prefix: FNP_ASSIGNMENT_NODE_PREFIX,
        line_limit: FNP_ASSIGNMENT_LINE_LIMIT,
        warn_threshold: FNP_ASSIGNMENT_WARN_THRESHOLD,
        key: key
      )
    end

    # Agrega la linea de mapeo Fine<->Forsta al final del ultimo nodo vigente
    # (busca el nodo actual por prefijo, no asume el nombre -- cambia con el
    # tiempo). Si ese nodo ya esta cerca del limite (~500 lineas), crea un nodo
    # nuevo automaticamente (ver rotate_script_node) y la linea arranca ahi, en
    # vez de seguir sumando al que esta por llenarse.
    #
    # key: opcional, para reusar una sesion ya abierta -- ver la nota sobre
    # "una sola sesion" en launch_survey, mismo motivo: si esto se llama justo
    # antes de un launch_survey (caso tipico: publicar el redirect), hay que
    # pasarle la MISMA key para evitar que Confirmit trate el Update y el
    # Launch como sesiones no relacionadas.
    def append_fnp_assignment(fine_project_code:, forsta_project_id:, project_id: FNP_ASSIGNMENT_PROJECT_ID, key: nil)
      key ||= log_on
      status = check_fnp_assignment_limit(project_id: project_id, key: key)
      line = "if(f('Project')==\"#{fine_project_code}\"){f(\"fnp\").set(\"#{forsta_project_id}\");}"

      if status[:near_limit]
        rotate_script_node(project_id: project_id, current_node_name: status[:node_name], initial_script_code: line, key: key)
      else
        append_to_script_node(project_id: project_id, script_name: status[:node_name], line_to_append: line, key: key)
      end
    end

    AUTOMATIC_NODE_SUFFIX_PATTERN = /-Automatico(\d+)\z/

    # Crea un nodo de script nuevo, como hermano del nodo actual (mismo lugar
    # en el arbol), con el nombre del actual mas un sufijo "-AutomaticoN" que
    # se va incrementando (si el actual ya termina en "-AutomaticoN", el nuevo
    # es "-Automatico(N+1)", no se van encadenando sufijos). Confirmado que
    # _Objid_Xml="0" le indica a Confirmit que asigne un ID nuevo -- probado
    # contra un proyecto de test real (2026-08-23) antes de usarlo en produccion.
    def rotate_script_node(project_id:, current_node_name:, initial_script_code:, key: nil)
      base_name = current_node_name.sub(AUTOMATIC_NODE_SUFFIX_PATTERN, '')
      previous_n = current_node_name[AUTOMATIC_NODE_SUFFIX_PATTERN, 1].to_i
      new_node_name = "#{base_name}-Automatico#{previous_n + 1}"

      create_script_node(
        project_id: project_id,
        after_script_name: current_node_name,
        new_node_name: new_node_name,
        initial_script_code: initial_script_code,
        key: key
      )

      new_node_name
    end

    # Solo lectura: identifica el ultimo nodo de script (por prefijo de nombre,
    # no por posicion estructural -- pueden estar anidados dentro de un
    # Condition intermedio junto con otras carpetas/alertas que no son parte
    # de la secuencia) dentro de una carpeta dada, y cuenta sus lineas contra
    # el limite pasado. No escribe nada. Logica compartida por
    # check_incentive_assignment_limit y check_fnp_assignment_limit.
    def check_script_limit(project_id:, folder_name:, node_prefix:, line_limit:, warn_threshold:, key: nil)
      key ||= log_on
      response_body = get_questionnaire(key: key, project_id: project_id)

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!

      fault = doc.at_xpath('//Fault')
      raise "Confirmit GetQuestionnaire fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}" if fault

      folder = doc.xpath('//Folder').find { |node| node.at_xpath('Name')&.text == folder_name }
      raise "No se encontro la carpeta \"#{folder_name}\" en el proyecto #{project_id}" unless folder

      matching_nodes = folder.xpath('.//Script').select do |node|
        node.at_xpath('Name')&.text.to_s.start_with?(node_prefix)
      end
      last_script = matching_nodes.last
      raise "No se encontraron nodos \"#{node_prefix} ...\" dentro de \"#{folder_name}\"" unless last_script

      script_code = last_script.at_xpath('ScriptCode')&.text.to_s
      line_count = script_code.lines.count

      {
        node_name: last_script.at_xpath('Name')&.text,
        line_count: line_count,
        line_limit: line_limit,
        lines_remaining: line_limit - line_count,
        near_limit: line_count >= warn_threshold
      }
    end

    # Idioma usado en los nodos Email de las cartas ES (2058 = espanol); el
    # generador solo escribe el idioma castellano de estos nodos -- el
    # portugues (1046) de las plantillas "Brasil ..." se maneja igual, pasando
    # language_id: 1046 explicitamente, no hace falta un metodo separado.
    EMAIL_LANGUAGE_ES = 2058
    EMAIL_LANGUAGE_PT = 1046

    # Sobreescribe el Subject/BodyHtml (para el idioma dado) de un nodo Email
    # existente y lo renombra. Pensado para el PRIMER pais de cada idioma en un
    # proyecto (ej. "ESP Primera 2026" -> "SetUpAR-Primera-2026") -- reusa el
    # mismo nodo en vez de crear uno nuevo. El texto plano (BodyPlaintext) no
    # se toca a proposito: es siempre el mismo, no varia por pais/proyecto.
    def overwrite_and_rename_email(project_id:, current_name:, new_name:, subject:, body_html:, language_id: EMAIL_LANGUAGE_ES)
      schema = get_raw_survey_schema(project_id: project_id)
      updated_inner = apply_overwrite_and_rename_email_in_inner(
        schema[:inner],
        current_name: current_name,
        new_name: new_name,
        subject: subject,
        body_html: body_html,
        language_id: language_id
      )
      send_schema_update(project_id: project_id, key: schema[:key], attrs: schema[:attrs], updated_inner: updated_inner)
    end

    # Duplica un nodo Email existente (ya sobreescrito/renombrado, tipicamente
    # via overwrite_and_rename_email) para un pais/grupo adicional del mismo
    # idioma -- ej. de "SetUpAR-Primera-2026" sale "SetUpMX-Primera-2026" con
    # su propio Subject/BodyHtml. El nodo nuevo queda como hermano, al lado del
    # que se duplico. Confirmado que el atributo que hay que resetear para que
    # Confirmit asigne un ID nuevo es "EntityId" (no "_Objid_Xml", que es lo
    # que usan los nodos Script -- Email es otro subtipo de nodo con su propio
    # identificador). Probado contra un proyecto de test real (2026-08-24).
    def duplicate_email(project_id:, source_name:, new_name:, subject:, body_html:, language_id: EMAIL_LANGUAGE_ES)
      schema = get_raw_survey_schema(project_id: project_id)
      updated_inner = apply_duplicate_email_in_inner(
        schema[:inner],
        source_name: source_name,
        new_name: new_name,
        subject: subject,
        body_html: body_html,
        language_id: language_id
      )
      send_schema_update(project_id: project_id, key: schema[:key], attrs: schema[:attrs], updated_inner: updated_inner)
    end

    # Aplica una tanda completa de cartas generadas por el generador de link
    # (una por tipo x grupo de pais/idioma) contra un proyecto: para la primera
    # carta de cada idioma dentro de un mismo tipo usa overwrite_and_rename_email
    # (pisa el modelo existente), y para el resto usa duplicate_email tomando
    # como fuente el nodo recien renombrado -- no el nombre original, que ya
    # dejo de existir una vez renombrado. cartas es un array de hashes (claves
    # simbolo) con: tipo, lang ('es'/'pt'), is_first_of_language, existing_name,
    # name, subject, body_html -- exactamente lo que devuelve buildAllCartas()
    # en el frontend, en el mismo orden (que importa: dentro de cada tipo, la
    # carta is_first_of_language de cada idioma siempre viene antes que las que
    # se duplican a partir de ella).
    # Optimizado para no releer/reescribir el schema completo (varios MB) por
    # cada carta -- eso es lo que hacia esto lento (~7-8s por lectura o
    # escritura grande, x2 por carta x N cartas). En vez de eso: UNA lectura,
    # todas las modificaciones encadenadas en memoria (son solo reemplazos de
    # texto puntuales sobre el string del schema, practicamente instantaneos),
    # y UNA sola escritura al final con todo adentro. De ~7-8 minutos para 30
    # cartas a un puñado de segundos (medido 2026-08-24/25).
    def apply_email_cartas(project_id:, cartas:)
      schema = get_raw_survey_schema(project_id: project_id)
      inner = schema[:inner]
      renamed_source = {}
      applied = []
      next_entity_id = -1

      cartas.each do |carta|
        lang = carta[:lang]
        language_id = lang == 'pt' ? EMAIL_LANGUAGE_PT : EMAIL_LANGUAGE_ES
        source_key = [carta[:tipo], lang]

        if carta[:is_first_of_language]
          inner = apply_overwrite_and_rename_email_in_inner(
            inner,
            current_name: carta[:existing_name],
            new_name: carta[:name],
            subject: carta[:subject],
            body_html: carta[:body_html],
            language_id: language_id
          )
          renamed_source[source_key] = carta[:name]
        else
          source_name = renamed_source[source_key]
          raise "No se aplico todavia la carta \"primera del idioma\" para #{source_key.join('/')} -- revisar el orden de \"cartas\"" unless source_name

          # new_entity_id unico por duplicado (no "0" fijo): Confirmit rechaza
          # un Update con mas de un nodo nuevo marcado "EntityId=0" a la vez
          # ("An item with the same key has already been added.", confirmado
          # 2026-08-25 -- con un solo carta se resuelve bien con "0", pero acá
          # se estan creando varios nodos nuevos en el mismo Update). Usar un
          # entero negativo distinto por cada uno evita la colision -- las
          # entidades reales de Confirmit son siempre positivas.
          inner = apply_duplicate_email_in_inner(
            inner,
            source_name: source_name,
            new_name: carta[:name],
            subject: carta[:subject],
            body_html: carta[:body_html],
            language_id: language_id,
            new_entity_id: next_entity_id
          )
          next_entity_id -= 1
        end

        applied << carta[:name]
      end

      send_schema_update(project_id: project_id, key: schema[:key], attrs: schema[:attrs], updated_inner: inner)
      applied
    end

    # Cuando la programacion es externa, el cliente redirige panelistas segun
    # una tabla de traduccion en dos pasos (ver A11 en build_definitions_script/
    # el generador de link): el script calcula un numero limpio por bloque
    # (primerid + contador, fijo por pais, 500 lugares c/u, sin superponer),
    # busca ese numero en "listadeids" para obtener el ID REAL del cliente
    # (Label -- puede ser cualquier string, ej. "CH0001", no necesariamente
    # numerico), y busca ese ID real en "listadelinks" para obtener el link.
    #
    # listadeids: Precode = primerid + posicion (numero limpio del bloque),
    #             Label = el ID real de esa fila (tal cual vino del archivo).
    # listadelinks: Precode = el ID real de esa fila, Label = el link.
    #
    # rows: array de {id:, link:} en el orden del archivo del cliente (fila 1
    # = primerid, fila 2 = primerid+1, etc). primer_id: inicio del bloque de
    # este pais (1, 501, 1001... segun el orden de paises seleccionados,
    # calculado igual que en el A11 del generador).
    #
    # Idempotente por pais: antes de agregar las filas nuevas, borra en
    # listadeids cualquier entrada con Precode dentro de
    # [primer_id, primer_id+499], y en listadelinks cualquier entrada cuyo
    # Precode coincida con algun Label de las que se acaban de borrar -- asi
    # resubir un pais reemplaza su bloque sin duplicar ni afectar otros
    # paises. Confirmado con el usuario 2026-08-26.
    CLIENT_LINKS_IDS_VAR = 'listadeids'
    CLIENT_LINKS_URLS_VAR = 'listadelinks'
    CLIENT_LINKS_BLOCK_SIZE = 500

    def upload_country_links(project_id:, primer_id:, rows:)
      schema = get_raw_survey_schema(project_id: project_id)
      inner = schema[:inner]

      ids_open, ids_close = find_single_variable_bounds(inner, CLIENT_LINKS_IDS_VAR)
      links_open, links_close = find_single_variable_bounds(inner, CLIENT_LINKS_URLS_VAR)

      block_end = primer_id + CLIENT_LINKS_BLOCK_SIZE - 1

      existing_ids = parse_single_answers(inner[ids_open...ids_close])
      removed_ids, kept_ids = existing_ids.partition { |a| a[:precode].to_i.between?(primer_id, block_end) }
      removed_real_ids = removed_ids.map { |a| a[:label] }

      existing_links = parse_single_answers(inner[links_open...links_close])
      kept_links = existing_links.reject { |a| removed_real_ids.include?(a[:precode]) }

      new_ids = rows.each_with_index.map { |row, i| { precode: (primer_id + i).to_s, label: row[:id].to_s } }
      new_links = rows.map { |row| { precode: row[:id].to_s, label: row[:link].to_s } }

      final_ids = (kept_ids + new_ids).sort_by { |a| a[:precode].to_i }
      final_links = kept_links + new_links

      ids_block_updated = replace_single_answers_content(inner[ids_open...ids_close], final_ids)
      links_block_updated = replace_single_answers_content(inner[links_open...links_close], final_links)

      # Aplicar el reemplazo que esta mas adelante en el documento primero,
      # para no invalidar los indices del otro.
      if ids_open < links_open
        inner = inner[0...links_open] + links_block_updated + inner[links_close..-1]
        inner = inner[0...ids_open] + ids_block_updated + inner[ids_close..-1]
      else
        inner = inner[0...ids_open] + ids_block_updated + inner[ids_close..-1]
        inner = inner[0...links_open] + links_block_updated + inner[links_close..-1]
      end

      send_schema_update(project_id: project_id, key: schema[:key], attrs: schema[:attrs], updated_inner: inner)
      { added: rows.length, removed: removed_ids.length }
    end

    private

    def get_questionnaire(key:, project_id:, endpoint: AUTHORING_ENDPOINT)
      envelope = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope #{SOAP_ENVELOPE_NAMESPACES}>
          <soap:Body>
            <GetQuestionnaire xmlns="http://firmglobal.com/Confirmit/webservices/">
              <key>#{xml_escape(key)}</key>
              <projectId>#{xml_escape(project_id)}</projectId>
              <projectSpecific>true</projectSpecific>
            </GetQuestionnaire>
          </soap:Body>
        </soap:Envelope>
      XML

      post_soap(
        endpoint: endpoint,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/GetQuestionnaire',
        envelope: envelope
      )
    end

    # Trae el SurveySchema completo de un proyecto via SurveyDesign, en crudo
    # (sin parsear), preservando el atributo Version del root -- necesario para
    # que Update lo acepte. Devuelve {attrs:, inner:} donde inner es el XML tal
    # cual vino, listo para modificar puntualmente y mandar de vuelta.
    def get_raw_survey_schema(project_id:, key: nil)
      key ||= log_on
      response_body = get_questionnaire(key: key, project_id: project_id, endpoint: SURVEY_DESIGN_ENDPOINT)

      match = response_body.match(/<GetQuestionnaireResult([^>]*)>(.*)<\/GetQuestionnaireResult>/m)
      raise "No se pudo leer el SurveySchema del proyecto #{project_id}: #{response_body[0, 300]}" unless match

      { key: key, attrs: match[1], inner: match[2] }
    end

    # Reemplaza el ScriptCode completo de un nodo de script, identificado por
    # nombre, y lo escribe de vuelta con Update via SurveyDesign. Confirmado que
    # esto funciona end-to-end contra un proyecto real (2026-08-21).
    def write_script_node(project_id:, script_name:, new_script_code:)
      update_script_node(project_id: project_id, script_name: script_name) { |_current_code| new_script_code }
    end

    # Agrega una linea al final del ScriptCode actual de un nodo, sin tocar lo
    # que ya habia. Pensado para ir sumando entradas (asignacion de incentivos,
    # mapeo Fine<->Forsta, etc.) a un nodo existente sin pisar el resto.
    def append_to_script_node(project_id:, script_name:, line_to_append:, key: nil)
      update_script_node(project_id: project_id, script_name: script_name, key: key) do |current_code|
        "#{current_code.chomp}\n#{line_to_append}"
      end
    end

    # Nucleo compartido de write_script_node/append_to_script_node: trae el
    # ScriptCode actual de un nodo (identificado por nombre exacto), le pasa el
    # texto actual al bloque para que devuelva el texto nuevo, y lo escribe de
    # vuelta con Update via SurveyDesign. Trabaja sobre el XML crudo (no
    # reserializa con Nokogiri) para no arriesgar modificar nada mas en un
    # arbol que puede pesar varios MB.
    def update_script_node(project_id:, script_name:, key: nil)
      schema = get_raw_survey_schema(project_id: project_id, key: key)

      name_needle = "<Name>#{script_name}</Name><ScriptCode>"
      start_index = schema[:inner].index(name_needle)
      raise "No se encontro el nodo de script \"#{script_name}\" en el proyecto #{project_id}" unless start_index

      code_start = start_index + name_needle.length
      code_end = schema[:inner].index('</ScriptCode>', code_start)
      raise "No se pudo determinar el final del ScriptCode de \"#{script_name}\"" unless code_end

      current_code = CGI.unescapeHTML(schema[:inner][code_start...code_end])
      new_code = yield(current_code)

      updated_inner = schema[:inner][0...code_start] + xml_escape(new_code) + schema[:inner][code_end..-1]
      send_schema_update(project_id: project_id, key: schema[:key], attrs: schema[:attrs], updated_inner: updated_inner)
    end

    # Inserta un nodo de script nuevo justo despues del nodo existente
    # "after_script_name" (mismo nivel del arbol, como hermano) y lo escribe
    # con Update via SurveyDesign. _Objid_Xml="0" es lo que le indica a
    # Confirmit que tiene que asignar un ID nuevo -- confirmado insertando un
    # nodo de prueba real y despues confirmando que aparece con GetQuestionnaire
    # (2026-08-23). Insertarlo como hermano inmediato del anterior (no al final
    # de la carpeta) es importante: los metodos check_script_limit/etc. toman
    # el ULTIMO nodo que matchea el prefijo por orden de documento, y la
    # carpeta puede tener otros nodos despues (alertas de mail, subcarpetas)
    # que no son parte de la secuencia.
    def create_script_node(project_id:, after_script_name:, new_node_name:, initial_script_code:, key: nil)
      schema = get_raw_survey_schema(project_id: project_id, key: key)

      after_needle = "<Name>#{after_script_name}</Name>"
      after_index = schema[:inner].index(after_needle)
      raise "No se encontro el nodo \"#{after_script_name}\" en el proyecto #{project_id}" unless after_index

      insert_at = schema[:inner].index('</Script>', after_index)
      raise "No se pudo determinar el final del nodo \"#{after_script_name}\"" unless insert_at

      insert_at += '</Script>'.length

      new_node_xml = '<Script _Objid_Xml="0" VersionTimestamp="0001-01-01T00:00:00" Deleted="false">' \
                      "<Name>#{xml_escape(new_node_name)}</Name>" \
                      "<ScriptCode>#{xml_escape(initial_script_code)}</ScriptCode>" \
                      '<UsePredefinedScript>false</UsePredefinedScript></Script>'

      updated_inner = schema[:inner][0...insert_at] + new_node_xml + schema[:inner][insert_at..-1]
      send_schema_update(project_id: project_id, key: schema[:key], attrs: schema[:attrs], updated_inner: updated_inner)
    end

    # Version "pura" (sin fetch/send propios) de overwrite_and_rename_email --
    # recibe y devuelve el string completo del schema (inner), para poder
    # encadenar varias modificaciones en memoria antes de un unico Update.
    # Sin esto, cada carta pagaba su propia lectura+escritura de varios MB
    # (ver apply_email_cartas).
    def apply_overwrite_and_rename_email_in_inner(inner, current_name:, new_name:, subject:, body_html:, language_id:)
      name_needle = "<Name>#{current_name}</Name>"
      name_idx = inner.index(name_needle)
      raise "No se encontro el nodo Email \"#{current_name}\"" unless name_idx

      email_open_start = inner.rindex('<Email ', name_idx)
      email_close = inner.index('</Email>', name_idx) + '</Email>'.length
      raise "No se pudo delimitar el nodo Email \"#{current_name}\"" unless email_open_start

      current_xml = inner[email_open_start...email_close]
      new_xml = current_xml.sub(name_needle, "<Name>#{new_name}</Name>")
      new_xml = replace_email_language_field(new_xml, field: 'Subject', language_id: language_id, new_value: subject)
      new_xml = replace_email_language_field(new_xml, field: 'BodyHtml', language_id: language_id, new_value: body_html)

      inner[0...email_open_start] + new_xml + inner[email_close..-1]
    end

    # Version "pura" (sin fetch/send propios) de duplicate_email -- ver
    # apply_overwrite_and_rename_email_in_inner arriba, mismo motivo.
    # new_entity_id: "0" funciona para un unico nodo nuevo por Update (caso
    # normal, un duplicate_email suelto). Cuando se crean VARIOS nodos nuevos
    # en el mismo Update (ver apply_email_cartas) hace falta un valor distinto
    # por cada uno -- Confirmit no acepta mas de un "0" simultaneo.
    def apply_duplicate_email_in_inner(inner, source_name:, new_name:, subject:, body_html:, language_id:, new_entity_id: '0')
      name_needle = "<Name>#{source_name}</Name>"
      name_idx = inner.index(name_needle)
      raise "No se encontro el nodo Email \"#{source_name}\"" unless name_idx

      email_open_start = inner.rindex('<Email ', name_idx)
      email_close = inner.index('</Email>', name_idx) + '</Email>'.length
      raise "No se pudo delimitar el nodo Email \"#{source_name}\"" unless email_open_start

      source_xml = inner[email_open_start...email_close]
      clone_xml = source_xml.sub(/EntityId="\d+"/, "EntityId=\"#{new_entity_id}\"")
      clone_xml = clone_xml.sub(name_needle, "<Name>#{new_name}</Name>")
      clone_xml = replace_email_language_field(clone_xml, field: 'Subject', language_id: language_id, new_value: subject)
      clone_xml = replace_email_language_field(clone_xml, field: 'BodyHtml', language_id: language_id, new_value: body_html)

      inner[0...email_close] + clone_xml + inner[email_close..-1]
    end

    # Reemplaza el valor de un campo por-idioma dentro de un nodo Email (ej.
    # <Subject Language="2058">texto viejo</Subject> o
    # <BodyHtml Language="2058">html viejo</BodyHtml>). Cuando el idioma no
    # tiene valor cargado el tag viene autocerrado (<Subject Language="2058" />,
    # sin contenido) -- ese caso tambien se contempla, insertando el contenido
    # antes del autocierre en vez de buscar un </Subject> que no existe.
    def replace_email_language_field(email_xml, field:, language_id:, new_value:)
      open_self_closed = "#{field} Language=\"#{language_id}\" />"
      open_with_content = "#{field} Language=\"#{language_id}\">"

      if (idx = email_xml.index(open_self_closed))
        email_xml[0...idx] + "#{field} Language=\"#{language_id}\">#{xml_escape(new_value)}</#{field}>" + email_xml[(idx + open_self_closed.length)..-1]
      elsif (idx = email_xml.index(open_with_content))
        content_start = idx + open_with_content.length
        content_end = email_xml.index("</#{field}>", content_start)
        raise "No se encontro el cierre de \"#{field}\" (idioma #{language_id})" unless content_end

        email_xml[0...content_start] + xml_escape(new_value) + email_xml[content_end..-1]
      else
        raise "No se encontro el campo \"#{field}\" para el idioma #{language_id}"
      end
    end

    # Delimita el nodo <Single ...>...</Single> completo de una variable de
    # tipo Single (choice unica), identificada por nombre exacto -- mismo
    # patron que los helpers de Email/Script, pero para variables de
    # cuestionario (ej. listadeids/listadelinks). No asume que sea la unica
    # <Single> del documento -- ancla en su propio <Name> hijo.
    def find_single_variable_bounds(inner, var_name)
      name_needle = "<Name>#{var_name}</Name>"
      name_idx = inner.index(name_needle)
      raise "No se encontro la variable \"#{var_name}\"" unless name_idx

      open_start = inner.rindex('<Single ', name_idx)
      close_end = inner.index('</Single>', name_idx)
      raise "No se pudo delimitar la variable \"#{var_name}\"" unless open_start && close_end

      [open_start, close_end + '</Single>'.length]
    end

    # Extrae {precode:, label:} de cada <Answer> dentro del XML de una
    # variable Single (o de su <SingleAnswers>...</SingleAnswers> a secas).
    # El label es el texto de Language="1046" -- alcanza con uno solo porque
    # ambos idiomas siempre llevan el mismo valor en estas dos variables
    # (confirmado con el usuario 2026-08-26).
    def parse_single_answers(single_xml)
      single_xml.scan(/<Answer Precode="([^"]*)"[^>]*>.*?<Text Language="1046">(.*?)<\/Text>.*?<\/Answer>/m).map do |precode, label|
        { precode: CGI.unescapeHTML(precode), label: CGI.unescapeHTML(label) }
      end
    end

    # Arma el XML de un <Answer> individual -- mismos atributos/estructura
    # que trae el modelo (StyleName/BackgroundColor/etc. vacios, TextsRight y
    # Expression vacios), copiando el mismo texto en los dos idiomas (1046 y
    # 2058) a proposito, aunque sobre.
    def build_single_answer_xml(precode, label)
      escaped_label = xml_escape(label)
      '<Answer Precode="' + xml_escape(precode) + '" StyleName="" BackgroundColor="" DefaultImageUrl="" HoverImageUrl="" SelectedImageUrl="">' \
        "<Texts><Text Language=\"1046\">#{escaped_label}</Text><Text Language=\"2058\">#{escaped_label}</Text></Texts>" \
        '<TextsRight /><Expression /></Answer>'
    end

    # Reemplaza el contenido de <SingleAnswers>...</SingleAnswers> dentro del
    # XML de una variable Single por la lista de answers dada (array de
    # {precode:, label:}), preservando el tag de apertura tal cual (con su
    # EntityId="" original).
    def replace_single_answers_content(single_xml, answers)
      open_idx = single_xml.index('<SingleAnswers')
      raise 'No se encontro <SingleAnswers> en la variable' unless open_idx

      tag_close_idx = single_xml.index('>', open_idx)
      close_tag_idx = single_xml.index('</SingleAnswers>', open_idx)
      raise 'No se pudo delimitar <SingleAnswers>' unless close_tag_idx

      new_answers_xml = answers.map { |a| build_single_answer_xml(a[:precode], a[:label]) }.join
      single_xml[0..tag_close_idx] + new_answers_xml + single_xml[close_tag_idx..-1]
    end

    # Arma y manda el Update via SurveyDesign -- nucleo compartido por todos
    # los metodos que escriben (scripts y emails).
    def send_schema_update(project_id:, key:, attrs:, updated_inner:)
      envelope = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope #{SOAP_ENVELOPE_NAMESPACES}>
          <soap:Body>
            <Update xmlns="http://firmglobal.com/Confirmit/webservices/">
              <key>#{xml_escape(key)}</key>
              <projectId>#{xml_escape(project_id)}</projectId>
              <schema#{attrs}>#{updated_inner}</schema>
            </Update>
          </soap:Body>
        </soap:Envelope>
      XML

      response_body = post_soap(
        endpoint: SURVEY_DESIGN_ENDPOINT,
        soap_action: 'http://firmglobal.com/Confirmit/webservices/Update',
        envelope: envelope
      )

      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!
      fault = doc.at_xpath('//Fault')
      raise "Confirmit Update fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}" if fault

      true
    end

    # Reemplaza las lineas "if(f('Pais')==...) {f('primerid').set(...);}"
    # dentro del bloque C4 (ver PRIMERID_BLOCK_MARKER) por las que vienen del
    # generador -- deja el comentario del C4 y el comentario "Otros paises"
    # de despues intactos, solo pisa las lineas de en medio. Si no encuentra
    # alguno de los dos marcadores, devuelve el tail sin tocar (mejor no
    # romper nada que fallar duro por un cambio de formato inesperado en el
    # template).
    def replace_primerid_block(tail, primerid_lines)
      marker_index = tail.index(PRIMERID_BLOCK_MARKER)
      return tail unless marker_index

      block_start = tail.index("\n\n", marker_index)
      return tail unless block_start

      block_start += 2
      block_end = tail.index(PRIMERID_BLOCK_END_MARKER, block_start)
      return tail unless block_end

      tail[0...block_start] + primerid_lines.strip + "\n\n\n" + tail[block_end..-1]
    end

    def extract_definitions_script_code(response_body)
      doc = Nokogiri::XML(response_body)
      doc.remove_namespaces!

      fault = doc.at_xpath('//Fault')
      raise "Confirmit GetQuestionnaire fault: #{fault.at_xpath('.//faultstring')&.text || fault.text}" if fault

      script_node = doc.xpath('//Script').find { |node| node.at_xpath('Name')&.text == DEFINITIONS_SCRIPT_NAME }
      raise "No se encontro el nodo de script \"#{DEFINITIONS_SCRIPT_NAME}\"" unless script_node

      script_code = script_node.at_xpath('ScriptCode')&.text
      raise "El nodo de script \"#{DEFINITIONS_SCRIPT_NAME}\" no tiene ScriptCode" if script_code.blank?

      script_code
    end

    # La clave de autorizacion que devuelve LogOnUser contiene un "&" literal
    # (confirmado por Forsta soporte, Sam, 2026-08-21, viendo un request que si
    # funciono). Sin escapar, ese "&" rompe el XML del envelope y explica por que
    # TODAS las llamadas a authoring.asmx fallaban con error 500 -- no era un
    # problema de permisos ni de servidor, era XML invalido de nuestro lado.
    def xml_escape(value)
      CGI.escapeHTML(value.to_s)
    end

    def post_soap(endpoint:, soap_action:, envelope:)
      uri = URI.parse(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'text/xml; charset=utf-8'
      request['SOAPAction'] = soap_action
      request.body = envelope

      # Net::HTTP devuelve el body en ASCII-8BIT por defecto -- sin esto,
      # concatenar esta respuesta con un string UTF-8 normal (ej. un script con
      # tildes/ñ) explota con Encoding::CompatibilityError. El SOAP response
      # siempre declara utf-8 en su XML declaration, asi que forzar el encoding
      # ahi es correcto, no un parche.
      http.request(request).body.dup.force_encoding('UTF-8')
    end
  end
end
