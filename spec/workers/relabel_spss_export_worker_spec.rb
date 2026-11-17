# frozen_string_literal: true

require 'rails_helper'
require 'zip'
require 'tmpdir'
require 'rubyXL'

RSpec.describe RelabelSpssExportWorker do
  # Sin esto, cada test intentaria pegarle a la API real de Confirmit --
  # se prueba aparte, fuera de la suite (ver ConfirmitVariableLookup y
  # ConfirmitSchemaFetcher). Devolver nil reproduce el comportamiento sin
  # API (fallback 100% a LabelParser), que es lo que validan estos tests.
  before { allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(nil) }
  # El zip original se guarda en S3 (ver EvidenceStore): en los tests no se toca la red.
  before { allow(ExportRelabeling::EvidenceStore).to receive(:save).and_return(nil) }

  let(:sps_content) do
    <<~SPS
      FILE HANDLE F1
       /NAME = 'c:\\temp\\data.asc'
       /LRECL=10.
      DATA LIST
       FIXED FILE = F1
       RECORDS=1
      /1
       Q1 1-2
      .
      VARIABLE LABELS
       Q1 'Pergunta (F1 - Texto de la pregunta)'
      .
      LIST.
    SPS
  end

  let(:zip_path) do
    dir = Dir.mktmpdir
    path = File.join(dir, 'test_export.zip')
    Zip::File.open(path, Zip::File::CREATE) do |zip|
      zip.get_output_stream('data.sps') { |f| f.write(sps_content) }
      zip.get_output_stream('data.asc') { |f| f.write("1 \n") }
    end
    path
  end

  # El compile real corre en una Lambda aparte (ver
  # ExportRelabeling::PsppLambdaClient) -- se stubea esa llamada en vez de
  # invocar PSPP/S3/Lambda de verdad. La validacion de que PSPP entiende la
  # sintaxis (y de que la Lambda compila un .sav real) ya se hizo a mano
  # contra un archivo real de Confirmit, fuera de la suite.
  def stub_pspp_success(&block)
    allow(ExportRelabeling::PsppLambdaClient).to receive(:compile) do |sps_path:, data_path:, output_path:|
      block&.call(sps_path, data_path)
      File.write(output_path, 'contenido sav simulado')
    end
  end

  def stub_mailer
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email).and_return(delivery)
    delivery
  end

  it 'extrae el zip, manda el .sps reescrito a la Lambda de PSPP, y manda el .sav resultante por mail' do
    stub_pspp_success
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(ExportDeliveryMailer).to have_received(:relabeled_export_email) do |recipients, project_id, output_paths, export_type:, **|
      expect(recipients).to eq(['destino@cliente.com'])
      expect(project_id).to eq('p123456')
      # El .sav compilado + la planilla de metadata (Dictionary/Quotas/
      # Report, ver #metadata_sheet_for) -- 2 archivos, no 1.
      expect(output_paths.map { |p| File.basename(p) }).to contain_exactly('data_relabeled.sav', 'Progress_report_data.xlsx')
      expect(export_type).to eq(:spss)
    end
  end

  # Diego: "el zip deberia aparecer con el mismo nombre del archivo
  # principal (no de loops)" -- mismo criterio que loop_section_title (el
  # nombre del loop siempre EXTIENDE al del principal), asi que el
  # basename mas corto gana sin importar el orden que devuelva Dir.glob.
  it 'con un archivo de loop ademas del principal, delivery_zip_name usa el nombre del principal (el mas corto), nunca el del loop' do
    dir = Dir.mktmpdir
    zip_path_with_loop = File.join(dir, 'test_export_loop.zip')
    Zip::File.open(zip_path_with_loop, Zip::File::CREATE) do |zip|
      zip.get_output_stream('data.sps') { |f| f.write(sps_content) }
      zip.get_output_stream('data.asc') { |f| f.write("1 \n") }
      zip.get_output_stream('data_fichas.sps') { |f| f.write(sps_content) }
      zip.get_output_stream('data_fichas.asc') { |f| f.write("1 \n") }
    end

    stub_pspp_success
    captured = nil
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, _paths, delivery_zip_name:, **|
      captured = delivery_zip_name
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com'])

    expect(captured).to eq('data_relabeled')
  end

  it 'reescribe el label compuesto y apunta el FILE HANDLE/SAVE OUTFILE a los paths fijos que espera la Lambda' do
    captured_sps = nil
    captured_data_path = nil
    stub_pspp_success { |sps_path, data_path| captured_sps = File.read(sps_path); captured_data_path = data_path }
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(captured_sps).to include("Q1 'Q1 : Pergunta | F1. Texto de la pregunta'")
    expect(captured_sps).to include("NAME = '#{ExportRelabeling::PsppLambdaClient::LAMBDA_DATA_PATH}'")
    expect(captured_sps).not_to include('c:\temp')
    expect(captured_sps).to include("SAVE OUTFILE='#{ExportRelabeling::PsppLambdaClient::LAMBDA_SAV_PATH}'")
    # El .asc real (extraido del zip) se le pasa aparte a PsppLambdaClient --
    # nunca se sube el que el FILE HANDLE original apuntaba en Windows.
    expect(File.basename(captured_data_path)).to eq('data.asc')
    # Confirmit siempre cierra la sintaxis con un "LIST." suelto -- sin
    # variables especificadas, lista TODAS las columnas de TODOS los casos
    # al log de pspp. Con un .asc real esto supero el limite de 6MB de
    # respuesta sincronica de Lambda (visto en un envio de prueba real).
    expect(captured_sps).not_to match(/^\s*LIST\s*\.\s*$/i)
    # Default de pspp (100) se pisa con cualquier export real -- subido
    # preventivamente para que un exceso de warnings no corte el
    # procesamiento de sintaxis a mitad de camino.
    expect(captured_sps).to start_with('SET MXWARNS=100000.')
  end

  # Confirmado contra un archivo real (p833174000229): el .asc con BOM
  # hacia que la PRIMERA fila se corriera de columna (RESPONSEID/RESPID
  # terminaban mezclados con STATUS/FECHACOMPLETA) -- DATA LIST FIXED lee
  # por posicion de byte, y esos 3 bytes invisibles corren todo lo demas.
  it 'saca el BOM UTF-8 del .asc antes de compilar, si lo trae' do
    dir = Dir.mktmpdir
    zip_with_bom = File.join(dir, 'test_export_bom.zip')
    Zip::File.open(zip_with_bom, Zip::File::CREATE) do |zip|
      zip.get_output_stream('data.sps') { |f| f.write(sps_content) }
      zip.get_output_stream('data.asc') { |f| f.write("\xEF\xBB\xBF1 \n".b) }
    end

    captured_data_content = nil
    allow(ExportRelabeling::PsppLambdaClient).to receive(:compile) do |data_path:, output_path:, **|
      captured_data_content = File.read(data_path, mode: 'rb')
      File.write(output_path, 'contenido sav simulado')
    end
    stub_mailer

    described_class.new.perform(zip_with_bom, 'p123456', ['destino@cliente.com'])

    expect(captured_data_content).to eq("1 \n")
    expect(captured_data_content.b).not_to start_with("\xEF\xBB\xBF".b)
  end

  it 'no toca el .asc si no trae BOM (deja el path original tal cual)' do
    captured_data_path = nil
    stub_pspp_success { |_sps_path, data_path| captured_data_path = data_path }
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(File.basename(captured_data_path)).to eq('data.asc')
  end

  # Caso real (p588393362171): 5 casos con las columnas corridas despues de
  # un texto con tilde -- PSPP cuenta bytes (la tilde son 2 en UTF-8) y el
  # DATA LIST de Confirmit cuenta caracteres. Ver SpssDataFilePreparer.
  it 'con tildes en los datos: manda el .asc a 1 byte por caracter y declara el ENCODING en el FILE HANDLE' do
    dir = Dir.mktmpdir
    zip_with_accents = File.join(dir, 'test_export_accents.zip')
    Zip::File.open(zip_with_accents, Zip::File::CREATE) do |zip|
      zip.get_output_stream('data.sps') { |f| f.write(sps_content) }
      zip.get_output_stream('data.asc') { |f| f.write("1 não\n".b) }
    end

    captured_sps = nil
    captured_data = nil
    stub_pspp_success { |sps_path, data_path| captured_sps = File.read(sps_path); captured_data = File.read(data_path, mode: 'rb') }
    stub_mailer

    described_class.new.perform(zip_with_accents, 'p123456', ['destino@cliente.com'])

    expect(captured_data).to eq("1 n\xE3o\n".b)
    expect(captured_sps).to include("NAME = '#{ExportRelabeling::PsppLambdaClient::LAMBDA_DATA_PATH}'\n /ENCODING='Windows-1252'\n /LRECL=10.")
  end

  it 'sin tildes en los datos: el FILE HANDLE no declara ENCODING (queda como siempre)' do
    captured_sps = nil
    stub_pspp_success { |sps_path, _data_path| captured_sps = File.read(sps_path) }
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(captured_sps).not_to include('ENCODING')
  end

  it 'borra el zip original y el directorio de trabajo al terminar' do
    stub_pspp_success
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(File.exist?(zip_path)).to be false
  end

  # Diego: retener un export arriesgaba perder eventos de farmacovigilancia. Si el SPSS no se puede
  # relabellear (sin permiso en Confirmit, schema ilegible, proyecto sin ID, fallo de la Lambda o del
  # proceso, o un .sav cuyos datos no coinciden con el .dat), se entrega IGUAL el zip original de
  # Confirmit -- mismo nombre, con un mensaje que dice que no esta relabelled -- y ademas se avisa a Fine.
  describe 'export sin relabellear: se entrega el original y se avisa' do
    let(:recipients) { ['destino@cliente.com', 'dcasar@fine-research.com'] }
    let(:alert_delivery) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }
    let(:client_mail) { {} }

    before do
      stub_pspp_success
      allow(ExportDeliveryMailer).to receive(:processing_alert_email).and_return(alert_delivery)
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |recipient_list, project_id, paths, **options|
        client_mail.merge!(recipients: recipient_list, project_id: project_id, paths: paths, **options)
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end
    end

    def expect_original_sent(alert_type, alert_recipients: ['dcasar@fine-research.com'], **extra)
      expect(client_mail).to include(paths: [zip_path], relabeled: false, export_type: :spss, recipients: recipients)
      expect(ExportDeliveryMailer).to have_received(:processing_alert_email).with(
        alert_recipients, anything,
        hash_including(export_type: :spss, alert_type: alert_type, original_sent: true, intended_recipients: recipients, **extra)
      )
      expect(ExportDeliveryMailer).not_to have_received(:processing_alert_email).with(anything, anything, hash_including(held: true))
    end

    it 'sin permiso en Confirmit: entrega el zip original (sin relabellear) y avisa a Fine con el motivo' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')

      described_class.new.perform(zip_path, 'p123456', recipients)

      expect_original_sent(:permission_denied, detail: 'Permission denied', filename: 'test_export.zip')
    end

    it 'si Confirmit no responde (otro error al leer el schema): entrega el original y avisa' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::SchemaUnavailableError, 'RuntimeError: timeout')

      described_class.new.perform(zip_path, 'p123456', recipients)

      expect_original_sent(:schema_unavailable, detail: 'RuntimeError: timeout')
    end

    it 'sin ID de proyecto: entrega el original (usa el titulo en el aviso) y ni intenta leer el schema' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)

      described_class.new.perform(zip_path, nil, recipients, nil, 'FP-18928G - Hidradenite')

      expect(ExportRelabeling::ConfirmitSchemaFetcher).not_to have_received(:call)
      expect_original_sent(:project_unidentified)
      expect(ExportDeliveryMailer).to have_received(:processing_alert_email).with(anything, 'FP-18928G - Hidradenite', anything)
    end

    it 'si la Lambda de PSPP falla: entrega el original y avisa con el error' do
      allow(ExportRelabeling::PsppLambdaClient).to receive(:compile).and_raise(StandardError, 'PSPP Lambda fallo')

      expect { described_class.new.perform(zip_path, 'p123456', recipients) }.not_to raise_error

      expect_original_sent(:processing_error, detail: 'StandardError: PSPP Lambda fallo')
    end

    it 'si la lista del envio no tiene ningun @fine-research.com, el aviso va a panel@fine-research.com' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')

      described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

      expect(client_mail).to include(paths: [zip_path], relabeled: false)
      expect(ExportDeliveryMailer).to have_received(:processing_alert_email)
        .with(['panel@fine-research.com'], 'p123456', hash_including(original_sent: true))
    end

    it 'si el aviso interno no sale, el original se entrego igual y no se levanta nada' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')
      allow(ExportDeliveryMailer).to receive(:processing_alert_email).and_raise(StandardError, 'sendgrid caido')

      expect { described_class.new.perform(zip_path, 'p123456', recipients) }.not_to raise_error

      expect(client_mail).to include(paths: [zip_path], relabeled: false)
    end

    it 'si el envio del original al cliente falla, la excepcion sube (Sidekiq reintenta): los datos no se pueden perder en silencio' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email).and_raise(StandardError, 'sendgrid caido')

      expect { described_class.new.perform(zip_path, 'p123456', recipients) }.to raise_error('sendgrid caido')
    end

    # Verificacion de datos (ver SavVerifier): un .sav con las columnas corridas respecto del .dat original
    # -- el caso de FP-18810G -- no se entrega; al cliente le llega el original de Confirmit (datos correctos)
    # y el aviso va SIEMPRE tambien a Diego.
    context 'verificacion del .sav contra el .dat' do
      it 'si los datos no coinciden: entrega el original de Confirmit (nunca el .sav dudoso) y avisa data_mismatch' do
        allow(ExportRelabeling::SavVerifier).to receive(:call)
          .and_raise(ExportRelabeling::SavVerifier::MismatchError, '120 de 21251 celdas no coinciden')

        described_class.new.perform(zip_path, 'p123456', recipients)

        expect_original_sent(:data_mismatch, detail: /120 de 21251 celdas/)
      end

      it 'el aviso del desfasaje va tambien a dcasar@fine-research.com aunque no este en el envio' do
        allow(ExportRelabeling::SavVerifier).to receive(:call)
          .and_raise(ExportRelabeling::SavVerifier::MismatchError, 'desfasaje')

        described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

        expect(client_mail).to include(paths: [zip_path], relabeled: false)
        expect(ExportDeliveryMailer).to have_received(:processing_alert_email).with(
          ['panel@fine-research.com', 'dcasar@fine-research.com'], 'p123456',
          hash_including(alert_type: :data_mismatch, original_sent: true)
        )
      end

      it 'si la verificacion misma no se puede hacer (formato no soportado, error al leer), entrega el relabelled como siempre' do
        allow(ExportRelabeling::SavVerifier).to receive(:call).and_raise(ExportRelabeling::SavVerifier::UnverifiableError, 'zlib')

        described_class.new.perform(zip_path, 'p123456', recipients)

        expect(client_mail).to include(relabeled: true)
        expect(ExportDeliveryMailer).not_to have_received(:processing_alert_email).with(anything, anything, hash_including(original_sent: true))
      end

      it 'verifica con el .sps (en el orden del cuestionario) y el .dat ORIGINAL' do
        verified = nil
        allow(ExportRelabeling::SavVerifier).to receive(:call) { |**args| verified = args }

        described_class.new.perform(zip_path, 'p123456', recipients)

        expect(verified[:sps_text]).to include('DATA LIST')
        expect(File.basename(verified[:data_path])).to eq('data.asc')
        expect(File.basename(verified[:sav_path])).to eq('data_relabeled.sav')
      end
    end

    it 'guarda una copia del zip original y la cita en el aviso (para reproducir el reclamo despues)' do
      allow(ExportRelabeling::EvidenceStore).to receive(:save).and_return('evidence/2026/11/16/p123456/spss_ab12_x.zip')
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')

      described_class.new.perform(zip_path, 'p123456', recipients)

      expect(ExportRelabeling::EvidenceStore).to have_received(:save).with(hash_including(project_id: 'p123456', export_type: :spss))
      expect(ExportDeliveryMailer).to have_received(:processing_alert_email)
        .with(anything, 'p123456', hash_including(evidence: 'evidence/2026/11/16/p123456/spss_ab12_x.zip'))
    end

    it 'deja una linea de log por export recibido y otra por entregado, con proyecto y archivo pero sin direcciones de mail' do
      worker = described_class.new
      lines = []
      allow(worker).to receive(:logger).and_return(instance_double(Logger, info: nil))
      allow(worker.logger).to receive(:info) { |line| lines << line }

      worker.perform(zip_path, 'p123456', recipients)

      expect(lines.grep(/export recibido: proyecto=p123456 archivo=test_export\.zip destinatarios=2/)).not_to be_empty
      expect(lines.grep(/export entregado: proyecto=p123456 destinatarios=2/)).not_to be_empty
      expect(lines.join).not_to include('@')
    end

    it 'el log distingue el export entregado sin relabellear' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')
      worker = described_class.new
      lines = []
      allow(worker).to receive(:logger).and_return(instance_double(Logger, info: nil))
      allow(worker.logger).to receive(:info) { |line| lines << line }

      worker.perform(zip_path, 'p123456', recipients)

      expect(lines.grep(/export entregado SIN relabellear: proyecto=p123456 archivo=test_export\.zip destinatarios=2/)).not_to be_empty
    end

    it 'con todo en orden se entrega el relabelled y no hay aviso de original' do
      described_class.new.perform(zip_path, 'p123456', recipients)

      expect(client_mail).to include(relabeled: true)
      expect(client_mail[:paths]).not_to eq([zip_path])
      expect(ExportDeliveryMailer).not_to have_received(:processing_alert_email).with(anything, anything, hash_including(original_sent: true))
    end
  end

  # Diego: "seria posible que en el zip del spss se habilitara tambien
  # agregar una planilla en excel que contuviera diccionario, quotas y
  # report (no los datos)? se pueden obtener estos datos si el envio
  # incluye los .dat y sps?" -- si, via ExportRelabeling::SpssDataListReader
  # (lee las posiciones de columna del DATA LIST) + el mismo
  # ExportRelabeling::ExportMetadataBuilder que ya usa Excel.
  describe 'planilla de metadata (Dictionary/Quotas/Report)' do
    let(:sps_content_con_status) do
      <<~SPS
        FILE HANDLE F1
         /NAME = 'c:\\temp\\data.asc'
         /LRECL=9.
        DATA LIST
         FIXED FILE = F1
         RECORDS=1
        /1
         STATUS 1-8 (A)
         Q1 9-9
        .
        VARIABLE LABELS
         STATUS 'status'
         Q1 'Pergunta (F1 - Texto de la pregunta)'
        .
      SPS
    end

    let(:zip_path_con_status) do
      dir = Dir.mktmpdir
      path = File.join(dir, 'test_export_status.zip')
      Zip::File.open(path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('data.sps') { |f| f.write(sps_content_con_status) }
        zip.get_output_stream('data.asc') { |f| f.write("complete1\ncomplete2\nscreened1\n") }
      end
      path
    end

    def captured_metadata_workbook(output_paths)
      metadata_path = output_paths.find { |p| p.end_with?('.xlsx') }
      RubyXL::Parser.parse(metadata_path)
    end

    it 'arma Progress_report_<nombre original>.xlsx con una hoja Dictionary (code/attribute/question + estadisticas, sin los datos)' do
      stub_pspp_success
      captured = nil
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, output_paths, **|
        captured = captured_metadata_workbook(output_paths)
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

      dictionary = captured.worksheets[0]
      expect(dictionary.sheet_name).to eq('Dictionary')
      expect(dictionary[0].cells.map(&:value)).to eq(
        ['Variable', 'Code', 'Attribute', 'Question', 'Mean', 'Min', 'Max', 'Nulls', '% Nulls', 'Zeros', 'Type', 'Answer Options']
      )
      expect(dictionary[1].cells.map(&:value)[0..3]).to eq(['Q1', 'F1', 'Pergunta', 'Texto de la pregunta'])
      # El compile a .sav escribe "data_relabeled.sps" en el MISMO
      # @work_dir -- si la metadata volviera a globear *.sps DESPUES de
      # compilar, ese archivo (con los labels ya reescritos en formato
      # "codigo | atributo | pregunta") se colaria como un loop aparte,
      # duplicando Q1 en una seccion espuria. Dictionary tiene que tener
      # SOLO 2 filas (header + Q1), nada mas.
      expect(dictionary.sheet_data.rows.length).to eq(2)
    end

    it 'agrega una hoja Quotas cuando el lookup resuelve cuotas, contando contra las filas reales del .dat' do
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
      allow(lookup).to receive(:variable_type).with('Q1').and_return('Single')
      allow(lookup).to receive(:quotas).and_return(
        [{ name: 'quota1', cells: [{ limit: 10, fields: [{ name: 'Q1', precode: nil, value: '1' }] }] }]
      )
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)
      stub_pspp_success

      captured = nil
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, output_paths, includes_quotas:, quota_lines:, **|
        captured = { workbook: captured_metadata_workbook(output_paths), includes_quotas: includes_quotas, quota_lines: quota_lines }
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_con_status, 'p123456', ['destino@cliente.com'])

      quotas_sheet = captured[:workbook].worksheets[1]
      expect(quotas_sheet.sheet_name).to eq('Quotas')
      expect(quotas_sheet[1].cells.map(&:value)).to eq(['quota1', 'Q1', '1', 10, 1, 9])
      expect(captured[:includes_quotas]).to be true
      # La cuota sigue abierta (1 de 10), y el cuerpo del mail las lista todas.
      expect(captured[:quota_lines]).to eq([{ quota: 'quota1', field: 'Q1', value: '1', target: 10, achieved: 1, pending: 9 }])
    end

    # Diego: "ordenemos siempre segun orden del cuestionario" (ver ExportRelabeling::ColumnOrder).
    it 'ordena las variables como el cuestionario: el DATA LIST del .sav y el Dictionary salen en el mismo orden' do
      sps_desordenado = <<~SPS
        FILE HANDLE F1
         /NAME = 'c:\\temp\\data.asc'
         /LRECL=10.
        DATA LIST
         FIXED FILE = F1
         RECORDS=1
        /1
         STATUS 1-8 (A)
         Q2 9-9
         Q1 10-10
        .
        VARIABLE LABELS
         STATUS 'status'
         Q1 'Pergunta 1 (F1 - Texto)'
         Q2 'Pergunta 2 (F2 - Texto)'
        .
      SPS
      dir = Dir.mktmpdir
      zip_desordenado = File.join(dir, 'test_export_orden.zip')
      Zip::File.open(zip_desordenado, Zip::File::CREATE) do |zip|
        zip.get_output_stream('data.sps') { |f| f.write(sps_desordenado) }
        zip.get_output_stream('data.asc') { |f| f.write("complete21\n") }
      end

      positions = { 'q1' => [1, 0, 0], 'q2' => [2, 0, 0] }
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position) { |name| positions[name.to_s.downcase] }
      allow(lookup).to receive(:quotas).and_return([])
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
      allow(lookup).to receive(:variable_type).and_return(nil)
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

      compiled_sps = nil
      stub_pspp_success { |sps_path, _data_path| compiled_sps = File.read(sps_path) }
      dictionary_names = nil
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, output_paths, **|
        dictionary = captured_metadata_workbook(output_paths).worksheets[0]
        dictionary_names = dictionary.sheet_data.rows.compact.map { |row| row.cells.first.value }
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_desordenado, 'p123456', ['destino@cliente.com'])

      expect(compiled_sps).to include(" STATUS 1-8 (A)\n Q1 10-10\n Q2 9-9\n")
      expect(dictionary_names.index('Q1')).to be < dictionary_names.index('Q2')
    end

    it 'parsea Quotas:/Report: del cuerpo del mail (email_body), igual que Excel' do
      stub_pspp_success
      captured = nil
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, output_paths, includes_quotas:, **|
        captured = { workbook: captured_metadata_workbook(output_paths), includes_quotas: includes_quotas }
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_con_status, 'p123456', ['destino@cliente.com'], "Quotas:\nQ1: 1=1")

      # Una cuota manual (ver ManualQuotaRequestParser) no tiene nombre
      # propio -- el "Quota" de la fila es la variable misma ("Q1").
      quotas_sheet = captured[:workbook].worksheets[1]
      expect(quotas_sheet.sheet_name).to eq('Quotas')
      expect(quotas_sheet[1].cells.map(&:value)).to eq(['Q1', 'Q1', '1', 1, 1, 0])
      expect(captured[:includes_quotas]).to be true
    end

    it 'si falla la lectura del DATA LIST para la metadata, igual manda los .sav (la planilla se omite, no el envio)' do
      allow(ExportRelabeling::SpssDataListReader).to receive(:call).and_raise(StandardError, 'DATA LIST inesperado')
      stub_pspp_success

      captured = {}
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, output_paths, relabeled:, includes_dictionary:, **|
        captured[:output_paths] = output_paths
        captured[:relabeled] = relabeled
        captured[:includes_dictionary] = includes_dictionary
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      expect { described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com']) }.not_to raise_error

      expect(captured[:output_paths].map { |p| File.basename(p) }).to eq(['data_relabeled.sav'])
      expect(captured[:relabeled]).to be true
      expect(captured[:includes_dictionary]).to be false
    end
  end
end
