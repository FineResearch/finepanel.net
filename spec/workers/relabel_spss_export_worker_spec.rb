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

    expect(captured_sps).to include("Q1 'F1 | Pergunta | Texto de la pregunta'")
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

  it 'borra el zip original y el directorio de trabajo al terminar' do
    stub_pspp_success
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(File.exist?(zip_path)).to be false
  end

  # Antes de esta feature, un fallo de PSPP hacia que #perform levantara y
  # Sidekiq reintentara -- si segia fallando, el cliente nunca recibia
  # nada. Diego: "lo mas seguro seria que si algo falla se envie lo mismo
  # que se recibio... cubrimos el riesgo de que los datos se enviaron
  # aunque el formato no fuera perfecto". Ahora ese fallo (la Lambda no
  # responde, el compile revienta, etc.) cae al zip original, sin
  # re-etiquetar, en vez de no mandar nada.
  it 'si la Lambda de PSPP falla, manda el zip original sin cambios en vez de nada' do
    allow(ExportRelabeling::PsppLambdaClient).to receive(:compile).and_raise(StandardError, 'PSPP Lambda fallo')

    captured = {}
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths, relabeled: true, **|
      captured[:output_paths] = output_paths
      captured[:relabeled] = relabeled
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    expect { described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com']) }.not_to raise_error

    expect(captured[:output_paths]).to eq([zip_path])
    expect(captured[:relabeled]).to be false
  end

  # Diego: "vamos a generar alertas para no tener fallos silenciosos" --
  # ver ExportRelabeling::ProcessingAlertNotifier. El pipeline sigue
  # (lookup nil, fallback a texto) pero alguien de Fine Research tiene que
  # enterarse de que hay que autorizar la API.
  it 'si el fetch del schema falla por permisos, avisa a los destinatarios @fine-research.com (y el pipeline sigue igual)' do
    allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
      .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')
    stub_pspp_success
    stub_mailer

    alert_delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:processing_alert_email).and_return(alert_delivery)

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com', 'dcasar@fine-research.com'])

    expect(ExportDeliveryMailer).to have_received(:processing_alert_email)
      .with(['dcasar@fine-research.com'], 'p123456', export_type: :spss, alert_type: :permission_denied)
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
        ['Variable', 'Code', 'Attribute', 'Question', 'Mean', 'Min', 'Max', 'Nulls', '% Nulls', 'Zeros', '', '', 'Answer Options']
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
      allow(lookup).to receive(:answer_options).and_return([])
      allow(lookup).to receive(:variable_type).with('Q1').and_return('Single')
      allow(lookup).to receive(:quotas).and_return(
        [{ name: 'quota1', cells: [{ limit: 10, fields: [{ name: 'Q1', precode: nil, value: '1' }] }] }]
      )
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)
      stub_pspp_success

      captured = nil
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, output_paths, includes_quotas:, completed_quotas:, **|
        captured = { workbook: captured_metadata_workbook(output_paths), includes_quotas: includes_quotas, completed_quotas: completed_quotas }
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_con_status, 'p123456', ['destino@cliente.com'])

      quotas_sheet = captured[:workbook].worksheets[1]
      expect(quotas_sheet.sheet_name).to eq('Quotas')
      expect(quotas_sheet[1].cells.map(&:value)).to eq(['quota1', 'Q1', '1', 10, 1, 9])
      expect(captured[:includes_quotas]).to be true
      expect(captured[:completed_quotas]).to eq([])
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
