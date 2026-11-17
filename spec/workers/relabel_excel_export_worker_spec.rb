# frozen_string_literal: true

require 'rails_helper'
require 'zip'
require 'rubyXL'
require 'tmpdir'

RSpec.describe RelabelExcelExportWorker do
  # Ver mismo comentario en relabel_spss_export_worker_spec.rb -- sin esto
  # cada test pegaria a la API real de Confirmit.
  before { allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(nil) }
  # El zip original se guarda en S3 (ver EvidenceStore): en los tests no se toca la red.
  before { allow(ExportRelabeling::EvidenceStore).to receive(:save).and_return(nil) }

  let(:sheet_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
      <row r="1"><c r="A1" t="str"><v>responseid</v></c><c r="B1" t="str"><v>f4_1 : Consultório/Clínica/Hospital PRIVADO (F4 - Dentre os locais?)</v></c></row>
      <row r="2"><c r="A2" t="str"><v>1</v></c><c r="B2" t="str"><v>2</v></c></row>
      <row r="3"><c r="A3" t="str"><v>2</v></c><c r="B3" t="str"><v>0</v></c></row>
      <row r="4"><c r="A4" t="str"><v>3</v></c></row>
      </sheetData></worksheet>
    XML
  end

  let(:zip_path) do
    dir = Dir.mktmpdir
    path = File.join(dir, 'test_export.zip')

    workbook_xml = '<?xml version="1.0" encoding="utf-8"?><x:workbook ' \
      'xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
      '<x:sheets><x:sheet name="Sheet1" sheetId="1" r:id="RID1" ' \
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" /></x:sheets></x:workbook>'
    rels_xml = '<?xml version="1.0" encoding="utf-8"?><Relationships ' \
      'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
      '<Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ' \
      'Target="/xl/worksheets/sheet.xml" Id="RID1" /></Relationships>'

    xlsx_path = File.join(dir, 'data.xlsx')
    Zip::File.open(xlsx_path, Zip::File::CREATE) do |xlsx|
      xlsx.get_output_stream('xl/workbook.xml') { |f| f.write(workbook_xml) }
      xlsx.get_output_stream('xl/_rels/workbook.xml.rels') { |f| f.write(rels_xml) }
      xlsx.get_output_stream('xl/worksheets/sheet.xml') { |f| f.write(sheet_xml) }
    end

    Zip::File.open(path, Zip::File::CREATE) { |zip| zip.add('data.xlsx', xlsx_path) }
    path
  end

  def stub_mailer
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email).and_return(delivery)
    delivery
  end

  it 'extrae el zip, reescribe los encabezados en UNA fila (VARIABLE : atributo | TITULO. pregunta), y manda el .xlsx resultante por mail' do
    # El worker borra su directorio de trabajo en el "ensure" apenas termina
    # perform -- hay que leer el archivo de salida DURANTE la llamada al
    # mailer (antes de que perform retorne), no despues.
    captured = {}
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |recipients, project_id, output_paths, export_type:, **|
      captured[:recipients] = recipients
      captured[:project_id] = project_id
      captured[:output_paths] = output_paths
      captured[:export_type] = export_type
      captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(captured[:recipients]).to eq(['destino@cliente.com'])
    expect(captured[:project_id]).to eq('p123456')
    expect(captured[:output_paths].length).to eq(1)
    expect(captured[:export_type]).to eq(:excel)

    sheet = captured[:workbook].worksheets[0]
    expect(sheet.sheet_name).to eq('Sheet1')
    expect(sheet[0].cells.map(&:value)).to eq(
      ['responseid', 'f4_1 : Consultório/Clínica/Hospital PRIVADO | F4. Dentre os locais?']
    )
    expect(sheet[1].cells.map(&:value)).to eq(%w[1 2])
  end

  # En un archivo de loop, Confirmit agrega un piping sin resolver pegado al
  # codigo de CADA variable (ej. "Q0A // ^f('hidden_ficha_nom')^"). Es
  # identico en toda columna y no ayuda a leer el encabezado de UNA sola fila
  # del formato nuevo, asi que se descarta ahi (el Dictionary lo conserva).
  it 'descarta del encabezado el piping de referencia al loop (una sola fila)' do
    dir = Dir.mktmpdir
    xlsx_path = File.join(dir, 'data.xlsx')
    zip_path = File.join(dir, 'loop_header.zip')

    workbook_xml = '<?xml version="1.0" encoding="utf-8"?><x:workbook ' \
      'xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
      '<x:sheets><x:sheet name="Sheet1" sheetId="1" r:id="RID1" ' \
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" /></x:sheets></x:workbook>'
    rels_xml = '<?xml version="1.0" encoding="utf-8"?><Relationships ' \
      'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
      '<Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ' \
      'Target="/xl/worksheets/sheet.xml" Id="RID1" /></Relationships>'
    sheet_xml_con_loop_ref = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
      <row r="1"><c r="A1" t="str"><v>q0a2_1 : CÂNCER (Q0A // ^f('hidden_ficha_nom')^ - O(a) Dr.(a) confirma? )</v></c></row>
      <row r="2"><c r="A2" t="str"><v>1</v></c></row>
      </sheetData></worksheet>
    XML

    Zip::File.open(xlsx_path, Zip::File::CREATE) do |xlsx|
      xlsx.get_output_stream('xl/workbook.xml') { |f| f.write(workbook_xml) }
      xlsx.get_output_stream('xl/_rels/workbook.xml.rels') { |f| f.write(rels_xml) }
      xlsx.get_output_stream('xl/worksheets/sheet.xml') { |f| f.write(sheet_xml_con_loop_ref) }
    end
    Zip::File.open(zip_path, Zip::File::CREATE) { |zip| zip.add('data.xlsx', xlsx_path) }

    captured = {}
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths, **|
      captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    sheet = captured[:workbook].worksheets[0]
    expect(sheet[0].cells.map(&:value)).to eq(['q0a2_1 : CÂNCER | Q0A. O(a) Dr.(a) confirma?'])
    expect(sheet[1].cells.map(&:value)).to eq(['1'])
  end

  it 'agrega una segunda hoja "Dictionary" con una fila por variable y sus estadisticas de columna' do
    captured = {}
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
      captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    dictionary = captured[:workbook].worksheets[1]
    expect(dictionary.sheet_name).to eq('Dictionary')
    expect(dictionary[0].cells.map(&:value)).to eq(
      ['Variable', 'Code', 'Attribute', 'Question', 'Mean', 'Min', 'Max', 'Nulls', '% Nulls', 'Zeros', 'Type',
       'Answer Options']
    )
    # Sin schema (lookup nil) el tipo se deduce de los datos de la columna.
    expect(dictionary[1].cells.map(&:value)).to eq(
      ['responseid', '-', '-', 'responseid', 2.0, 1.0, 3.0, 0, 0.0, 0, 'Numeric', '-']
    )
    expect(dictionary[2].cells.map(&:value)).to eq(
      ['f4_1', 'F4', 'Consultório/Clínica/Hospital PRIVADO', 'Dentre os locais?', 1.0, 0.0, 2.0, 1, 33.33, 1, 'Numeric', '-']
    )
  end

  # Diego: "ordenemos siempre segun orden del cuestionario" (ver ExportRelabeling::ColumnOrder).
  describe 'orden de columnas del cuestionario' do
    let(:sheet_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        <row r="1"><c r="A1" t="str"><v>responseid</v></c><c r="B1" t="str"><v>f4_2 : Dos | F4. Pregunta</v></c><c r="C1" t="str"><v>f4_1 : Uno | F4. Pregunta</v></c></row>
        <row r="2"><c r="A2" t="str"><v>1</v></c><c r="B2" t="str"><v>dato_dos</v></c><c r="C2" t="str"><v>dato_uno</v></c></row>
        </sheetData></worksheet>
      XML
    end

    it 'deja las columnas en el orden del cuestionario, con sus datos, y no mueve las que el schema no conoce' do
      positions = { 'f4_1' => [1, 0, 0], 'f4_2' => [1, 1, 0] }
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position) { |name| positions[name.to_s.downcase] }
      allow(lookup).to receive(:quotas).and_return([])
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

      captured = nil
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, output_paths, **|
        sheet = RubyXL::Parser.parse(output_paths.first).worksheets[0]
        captured = { header: sheet[0].cells.map(&:value), row: sheet[1].cells.map(&:value) }
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

      expect(captured[:header]).to eq(['responseid', 'f4_1 : Uno | F4. Pregunta', 'f4_2 : Dos | F4. Pregunta'])
      expect(captured[:row]).to eq(%w[1 dato_uno dato_dos])
    end
  end

  describe 'variables faltantes del cuestionario' do
    def lookup_double(units)
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:quotas).and_return([])
      allow(lookup).to receive(:questionnaire_variables).and_return(units)
      lookup
    end

    # Las columnas del archivo de prueba son "responseid" y "f4_1".
    it 'le pasa al aviso interno las preguntas del cuestionario que no vinieron en el export' do
      units = [
        { name: 'f4', title: 'F4', names: %w[f4] },
        { name: 'q5a', title: 'Q5A', names: %w[q5a] }
      ]
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup_double(units))
      stub_mailer
      allow(ExportRelabeling::ProcessingAlertNotifier).to receive(:call)

      described_class.new.perform(zip_path, 'p123456', ['dcasar@fine-research.com'])

      expect(ExportRelabeling::ProcessingAlertNotifier).to have_received(:call).with(
        hash_including(missing_variables: [{ name: 'q5a', title: 'Q5A' }])
      )
    end

    it 'no le pasa nada si todas las preguntas vinieron' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_return(lookup_double([{ name: 'f4', title: 'F4', names: %w[f4] }]))
      stub_mailer
      allow(ExportRelabeling::ProcessingAlertNotifier).to receive(:call)

      described_class.new.perform(zip_path, 'p123456', ['dcasar@fine-research.com'])

      expect(ExportRelabeling::ProcessingAlertNotifier).to have_received(:call).with(hash_including(missing_variables: []))
    end

    it 'si no hay schema (lookup nil) no se avisa nada ni se rompe el envio' do
      stub_mailer
      allow(ExportRelabeling::ProcessingAlertNotifier).to receive(:call)

      expect { described_class.new.perform(zip_path, 'p123456', ['dcasar@fine-research.com']) }.not_to raise_error

      expect(ExportRelabeling::ProcessingAlertNotifier).to have_received(:call).with(hash_including(missing_variables: []))
    end

    # El cliente recibe la base pase lo que pase con la deteccion.
    it 'si la deteccion revienta, igual manda el export' do
      lookup = lookup_double(nil)
      allow(lookup).to receive(:questionnaire_variables).and_raise(StandardError, 'schema raro')
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)
      delivery = stub_mailer

      described_class.new.perform(zip_path, 'p123456', ['dcasar@fine-research.com'])

      expect(delivery).to have_received(:deliver_now)
    end
  end

  it 'borra el zip original y el directorio de trabajo al terminar' do
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(File.exist?(zip_path)).to be false
  end

  context 'con cuotas (ver ExportRelabeling::QuotaProgressBuilder)' do
    let(:sheet_xml_with_status) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        <row r="1"><c r="A1" t="str"><v>status</v></c><c r="B1" t="str"><v>s0</v></c></row>
        <row r="2"><c r="A2" t="str"><v>complete</v></c><c r="B2" t="str"><v>1</v></c></row>
        <row r="3"><c r="A3" t="str"><v>complete</v></c><c r="B3" t="str"><v>1</v></c></row>
        <row r="4"><c r="A4" t="str"><v>screened</v></c><c r="B4" t="str"><v>1</v></c></row>
        </sheetData></worksheet>
      XML
    end

    let(:zip_path_with_status) do
      dir = Dir.mktmpdir
      path = File.join(dir, 'test_export.zip')

      workbook_xml = '<?xml version="1.0" encoding="utf-8"?><x:workbook ' \
        'xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
        '<x:sheets><x:sheet name="Sheet1" sheetId="1" r:id="RID1" ' \
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" /></x:sheets></x:workbook>'
      rels_xml = '<?xml version="1.0" encoding="utf-8"?><Relationships ' \
        'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
        '<Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ' \
        'Target="/xl/worksheets/sheet.xml" Id="RID1" /></Relationships>'

      xlsx_path = File.join(dir, 'data.xlsx')
      Zip::File.open(xlsx_path, Zip::File::CREATE) do |xlsx|
        xlsx.get_output_stream('xl/workbook.xml') { |f| f.write(workbook_xml) }
        xlsx.get_output_stream('xl/_rels/workbook.xml.rels') { |f| f.write(rels_xml) }
        xlsx.get_output_stream('xl/worksheets/sheet.xml') { |f| f.write(sheet_xml_with_status) }
      end

      Zip::File.open(path, Zip::File::CREATE) { |zip| zip.add('data.xlsx', xlsx_path) }
      path
    end

    it 'agrega una hoja "Quotas" cuando el lookup resuelve cuotas, contando contra las filas reales, con el header en negrita y fondo amarillo' do
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
      allow(lookup).to receive(:variable_type).with('s0').and_return('Single')
      allow(lookup).to receive(:quotas).and_return(
        [{ name: 'quota1', cells: [{ limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] }] }]
      )
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

      captured = {}
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths, includes_quotas:, **|
        captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
        captured[:includes_quotas] = includes_quotas
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_with_status, 'p123456', ['destino@cliente.com'])

      quotas_sheet = captured[:workbook].worksheets[2]
      expect(quotas_sheet.sheet_name).to eq('Quotas')
      expect(quotas_sheet[0].cells.map(&:value)).to eq(%w[Quota Variable Value Goal Achieved Pending])
      expect(quotas_sheet[0][0].is_bolded).to be true
      expect(quotas_sheet[0][0].fill_color).to eq('FFFF00')
      expect(quotas_sheet[1].cells.map(&:value)).to eq(['quota1', 's0', '1', 88, 2, 86])
      expect(captured[:includes_quotas]).to be true
    end

    # Diego: mostrar en el cuerpo del mail todas las cuotas con su pendiente
    # (ver ExportRelabeling::QuotaLines), sin tener que abrir el Excel.
    it 'pasa todas las cuotas (con su pendiente) al mailer como quota_lines' do
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
      allow(lookup).to receive(:variable_type).with('s0').and_return('Single')
      allow(lookup).to receive(:quotas).and_return(
        [{ name: 'quota1', cells: [{ limit: 2, fields: [{ name: 's0', precode: nil, value: '1' }] }] }]
      )
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

      captured = {}
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, _paths, quota_lines:, **|
        captured[:quota_lines] = quota_lines
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_with_status, 'p123456', ['destino@cliente.com'])

      expect(captured[:quota_lines]).to eq([{ quota: 'quota1', field: 's0', value: '1', target: 2, achieved: 2, pending: 0 }])
    end

    it 'no agrega hoja de cuotas si el lookup no resuelve (fetch de schema fallo)' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(nil)

      captured = {}
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
        captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_with_status, 'p123456', ['destino@cliente.com'])

      expect(captured[:workbook].worksheets.map(&:sheet_name)).not_to include('Quotas')
    end

    it 'excluye del proceso automatico las cuotas que referencian una variable de tipo Grid (fichas)' do
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
      allow(lookup).to receive(:variable_type).with('qregion').and_return('Grid')
      allow(lookup).to receive(:quotas).and_return(
        [{ name: 'quota3', cells: [{ limit: 95, fields: [{ name: 'qregion', precode: nil, value: 'A' }] }] }]
      )
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

      captured = {}
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
        captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_with_status, 'p123456', ['destino@cliente.com'])

      expect(captured[:workbook].worksheets.map(&:sheet_name)).not_to include('Quotas')
    end

    # Diego: "si algun proceso falla se omite ese proceso y no se para el
    # reenvio de la base" -- una excepcion inesperada calculando las cuotas
    # automaticas (ej. el schema de Confirmit vino con una forma rara) no
    # debe frenar el envio del archivo base.
    it 'si el calculo de cuotas automaticas revienta (excepcion inesperada), igual manda el archivo base sin la hoja "Quotas"' do
      lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
      allow(lookup).to receive(:call).and_return(nil)
      allow(lookup).to receive(:column_profile).and_return(nil)
      allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
      allow(lookup).to receive(:quotas).and_raise(StandardError, 'schema inesperado')
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

      captured = {}
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
        captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      expect { described_class.new.perform(zip_path_with_status, 'p123456', ['destino@cliente.com']) }.not_to raise_error

      expect(captured[:workbook].worksheets.map(&:sheet_name)).not_to include('Quotas')
      expect(captured[:workbook].worksheets[0].sheet_name).to eq('Sheet1')
    end

    # "fichaestado" es Hidden y CUSTOM de cada proyecto (a diferencia de
    # "status") -- el worker busca el label "completa" (con fallback
    # "complete"/"c") entre las respuestas reales de esa variable, sin
    # asumir ningun precode fijo (Diego: "el criterio que importa es que
    # el label sea completa... mas alla del valor del precode").
    context 'con un archivo de loop (ej. fichas) ademas del principal' do
      let(:fichas_sheet_xml) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
          <row r="1"><c r="A1" t="str"><v>fichaestado</v></c><c r="B1" t="str"><v>qestado_1</v></c></row>
          <row r="2"><c r="A2" t="str"><v>completa</v></c><c r="B2" t="str"><v>1</v></c></row>
          <row r="3"><c r="A3" t="str"><v>incompleta</v></c><c r="B3" t="str"><v>1</v></c></row>
          </sheetData></worksheet>
        XML
      end

      let(:zip_path_with_loop) do
        dir = Dir.mktmpdir
        path = File.join(dir, 'test_export.zip')

        workbook_xml = '<?xml version="1.0" encoding="utf-8"?><x:workbook ' \
          'xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
          '<x:sheets><x:sheet name="Sheet1" sheetId="1" r:id="RID1" ' \
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" /></x:sheets></x:workbook>'
        rels_xml = '<?xml version="1.0" encoding="utf-8"?><Relationships ' \
          'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
          '<Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ' \
          'Target="/xl/worksheets/sheet.xml" Id="RID1" /></Relationships>'

        main_path = File.join(dir, 'main.xlsx')
        Zip::File.open(main_path, Zip::File::CREATE) do |xlsx|
          xlsx.get_output_stream('xl/workbook.xml') { |f| f.write(workbook_xml) }
          xlsx.get_output_stream('xl/_rels/workbook.xml.rels') { |f| f.write(rels_xml) }
          xlsx.get_output_stream('xl/worksheets/sheet.xml') { |f| f.write(sheet_xml_with_status) }
        end

        fichas_path = File.join(dir, 'main_fichas.xlsx')
        Zip::File.open(fichas_path, Zip::File::CREATE) do |xlsx|
          xlsx.get_output_stream('xl/workbook.xml') { |f| f.write(workbook_xml) }
          xlsx.get_output_stream('xl/_rels/workbook.xml.rels') { |f| f.write(rels_xml) }
          xlsx.get_output_stream('xl/worksheets/sheet.xml') { |f| f.write(fichas_sheet_xml) }
        end

        Zip::File.open(path, Zip::File::CREATE) do |zip|
          zip.add('main.xlsx', main_path)
          zip.add('main_fichas.xlsx', fichas_path)
        end
        path
      end

      # Diego: "el zip deberia aparecer con el mismo nombre del archivo
      # principal (no de loops)" -- el principal es el que tiene la
      # variable de sistema "status" (ver #main_file_basename), nunca el
      # de loop, sin importar el orden en que Dir.glob devuelva los xlsx.
      it 'delivery_zip_name usa el nombre del archivo principal (el que tiene "status"), nunca el del loop' do
        captured = nil
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_r, _p, _paths, delivery_zip_name:, **|
          captured = delivery_zip_name
          instance_double(ActionMailer::MessageDelivery, deliver_now: true)
        end

        described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com'])

        expect(captured).to eq('main_relabeled')
      end

      it 'resuelve "completa" buscando el label entre las respuestas, no asumiendo un precode fijo' do
        lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
        allow(lookup).to receive(:call).and_return(nil)
        allow(lookup).to receive(:column_profile).and_return(nil)
        allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
        allow(lookup).to receive(:variable_type).with('qestado_1').and_return('Multi')
        allow(lookup).to receive(:answer_option_matching).with('fichaestado', %w[completa complete c]).and_return([nil, 'completa'])
        allow(lookup).to receive(:quotas).and_return(
          [{ name: 'quota5', cells: [{ limit: 10, fields: [{ name: 'qestado_1', precode: '1', value: '1' }] }] }]
        )
        allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

        captured = {}
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
          main_output = output_paths.find { |p| !p.include?('fichas') }
          captured[:workbook] = RubyXL::Parser.parse(main_output)
          instance_double(ActionMailer::MessageDelivery, deliver_now: true)
        end

        described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com'])

        quotas_sheet = captured[:workbook].worksheets.find { |s| s.sheet_name == 'Quotas' }
        # Solo la fila con fichaestado="completa" cuenta -- si el codigo
        # comparara contra un precode crudo en vez del label resuelto,
        # esto daria 0.
        expect(quotas_sheet[1].cells.map(&:value)).to eq(['quota5', 'qestado_1', '1', 10, 1, 9])
      end

      it 'consolida el Diccionario del archivo principal con las variables del loop debajo, con su titulo' do
        lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
        allow(lookup).to receive(:call).and_return(nil)
        allow(lookup).to receive(:column_profile).and_return(nil)
        allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
        allow(lookup).to receive(:answer_option_matching).and_return([nil, 'completa'])
        allow(lookup).to receive(:quotas).and_return([])
        allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

        captured = {}
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
          main_output = output_paths.find { |p| !p.include?('fichas') }
          captured[:workbook] = RubyXL::Parser.parse(main_output)
          instance_double(ActionMailer::MessageDelivery, deliver_now: true)
        end

        described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com'])

        dictionary = captured[:workbook].worksheets.find { |s| s.sheet_name == 'Dictionary' }
        variable_names = (0..dictionary.sheet_data.rows.length - 1).map { |i| dictionary[i]&.cells&.first&.value }

        # status/s0 (principal) primero, despues una fila en blanco, el
        # titulo "Fichas", y recien ahi fichaestado/qestado_1 (el loop).
        expect(variable_names).to eq(['Variable', 'status', 's0', nil, 'Fichas', 'Variable', 'fichaestado', 'qestado_1'])
      end

      it 'agrega las cuotas declaradas a mano en el mail abajo de las automaticas, separadas por una fila en blanco y con su propio header repetido' do
        lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
        allow(lookup).to receive(:call).and_return(nil)
        allow(lookup).to receive(:column_profile).and_return(nil)
        allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
        allow(lookup).to receive(:variable_type).with('s0').and_return('Single')
        allow(lookup).to receive(:answer_option_matching).and_return([nil, 'completa'])
        allow(lookup).to receive(:answer_label).and_return(nil)
        allow(lookup).to receive(:quotas).and_return(
          [{ name: 'quota1', cells: [{ limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] }] }]
        )
        allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

        captured = {}
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
          main_output = output_paths.find { |p| !p.include?('fichas') }
          captured[:workbook] = RubyXL::Parser.parse(main_output)
          instance_double(ActionMailer::MessageDelivery, deliver_now: true)
        end

        described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com'], "Quotas:\ns0: 1=10")

        quotas_sheet = captured[:workbook].worksheets.find { |s| s.sheet_name == 'Quotas' }
        rows = (0..quotas_sheet.sheet_data.rows.length - 1).map { |i| quotas_sheet[i]&.cells&.map(&:value) }

        expect(rows[0]).to eq(%w[Quota Variable Value Goal Achieved Pending])
        expect(rows[1]).to eq(['quota1', 's0', '1', 88, 2, 86])
        expect(rows[2]).to eq([nil, nil, nil, nil, nil, nil])
        expect(rows[3]).to eq(%w[Quota Variable Value Goal Achieved Pending])
        expect(rows[4]).to eq(['s0', 's0', '1', 10, 2, 8])
      end

      it 'arma la hoja "Report" con un crosstab para cada cruce pedido en "Report:", sin la fila de eje redundante' do
        lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
        allow(lookup).to receive(:call).and_return(nil)
        allow(lookup).to receive(:column_profile).and_return(nil)
        allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
        allow(lookup).to receive(:answer_option_matching).and_return([nil, 'completa'])
        allow(lookup).to receive(:quotas).and_return([])
        allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

        captured = {}
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths, includes_report:, **|
          main_output = output_paths.find { |p| !p.include?('fichas') }
          captured[:workbook] = RubyXL::Parser.parse(main_output)
          captured[:includes_report] = includes_report
          instance_double(ActionMailer::MessageDelivery, deliver_now: true)
        end

        described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com'], "Report:\nqestado_1 x fichaestado")

        report = captured[:workbook].worksheets.find { |s| s.sheet_name == 'Report' }
        rows = (0..report.sheet_data.rows.length - 1).map { |i| report[i]&.cells&.map(&:value) }

        expect(rows[0]).to eq(['qestado_1 x fichaestado'])
        expect(report[0][0].is_bolded).to be true
        expect(report[0][0].fill_color).to eq('FFFF00')
        expect(rows[1]).to eq([nil, 'completa', 'Total'])
        expect(rows[2]).to eq(['1', 1, 1])
        expect(captured[:includes_report]).to be true
        expect(rows[3]).to eq(['Total', 1, 1])
      end

      # Bug real (encontrado por Diego): sin schema resuelto (lookup nil, el
      # caso normal cuando Confirmit no responde) Y con un archivo de loop
      # de por medio, `status_config` llamaba `lookup.answer_label_matching`
      # sobre un `nil` -- reventaba TODO el worker antes de mandar nada, ni
      # siquiera el archivo base. El `before` de este spec ya deja el
      # lookup en nil por defecto (ver arriba), asi que este test no
      # necesita ningun stub extra para reproducir el caso.
      it 'no revienta el worker si el schema no se pudo resolver (lookup nil) y hay un archivo de loop -- bug real ya corregido' do
        captured = {}
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
          captured[:output_paths] = output_paths
          instance_double(ActionMailer::MessageDelivery, deliver_now: true)
        end

        expect { described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com']) }.not_to raise_error

        expect(captured[:output_paths].length).to eq(2)
      end

      it 'si el crosstab de "Report" revienta (excepcion inesperada), igual manda el archivo base sin esa hoja' do
        lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
        allow(lookup).to receive(:call).and_return(nil)
        allow(lookup).to receive(:column_profile).and_return(nil)
        allow(lookup).to receive(:column_position).and_return(nil)
      allow(lookup).to receive(:questionnaire_variables).and_return(nil)
        allow(lookup).to receive(:answer_option_matching).and_return([nil, 'completa'])
        allow(lookup).to receive(:quotas).and_return([])
        allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)
        allow(ExportRelabeling::CrosstabBuilder).to receive(:call).and_raise(StandardError, 'schema inesperado')

        captured = {}
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
          main_output = output_paths.find { |p| !p.include?('fichas') }
          captured[:workbook] = RubyXL::Parser.parse(main_output)
          instance_double(ActionMailer::MessageDelivery, deliver_now: true)
        end

        expect do
          described_class.new.perform(zip_path_with_loop, 'p123456', ['destino@cliente.com'], "Report:\nqestado_1 x fichaestado")
        end.not_to raise_error

        expect(captured[:workbook].worksheets.map(&:sheet_name)).not_to include('Report')
        expect(captured[:workbook].worksheets[0].sheet_name).to eq('Sheet1')
      end
    end
  end

  # Diego: retener el Excel arriesgaba perder eventos de farmacovigilancia. Si el export no se puede
  # relabellear (sin permiso en Confirmit, schema ilegible, proyecto sin ID, fallo del proceso), se
  # entrega IGUAL el zip original de Confirmit -- mismo nombre, con un mensaje que dice que no esta
  # relabelled -- y ademas se avisa a Fine. (El SPSS sigue reteniendose con aviso.)
  describe 'export sin relabellear: se entrega el original y se avisa' do
    let(:recipients) { ['destino@cliente.com', 'dcasar@fine-research.com'] }
    let(:alert_delivery) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }
    let(:client_mail) { {} }

    before do
      allow(ExportDeliveryMailer).to receive(:processing_alert_email).and_return(alert_delivery)
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |recipient_list, project_id, paths, **options|
        client_mail.merge!(recipients: recipient_list, project_id: project_id, paths: paths, **options)
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end
    end

    def expect_original_sent(alert_type, **extra)
      expect(client_mail).to include(paths: [zip_path], relabeled: false, export_type: :excel, recipients: recipients)
      expect(ExportDeliveryMailer).to have_received(:processing_alert_email).with(
        ['dcasar@fine-research.com'], anything,
        hash_including(export_type: :excel, alert_type: alert_type, original_sent: true, intended_recipients: recipients, **extra)
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

    it 'sin ID de proyecto: entrega el original (usa el titulo para nombrarlo en el aviso) y ni intenta leer el schema' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)

      described_class.new.perform(zip_path, nil, recipients, nil, 'FP-18928G - Hidradenite')

      expect(ExportRelabeling::ConfirmitSchemaFetcher).not_to have_received(:call)
      expect_original_sent(:project_unidentified)
      expect(ExportDeliveryMailer).to have_received(:processing_alert_email).with(anything, 'FP-18928G - Hidradenite', anything)
    end

    it 'si el pipeline central revienta (ej. el Excel no se puede leer): entrega el original y avisa con el error' do
      allow(ExportRelabeling::ExcelReader).to receive(:call).and_raise(StandardError, 'archivo corrupto')

      expect { described_class.new.perform(zip_path, 'p123456', recipients) }.not_to raise_error

      expect_original_sent(:processing_error, detail: 'StandardError: archivo corrupto')
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

    it 'el original se entrega con el titulo y el filtro de entrevistas, como un envio normal' do
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')

      described_class.new.perform(zip_path, 'p123456', recipients, nil, 'FP-1 Proyecto', 'Complete')

      expect(client_mail).to include(project_title: 'FP-1 Proyecto', interview_status_filter: 'Complete')
    end

    it 'con todo en orden se entrega el relabelled y no hay aviso de original' do
      described_class.new.perform(zip_path, 'p123456', recipients)

      expect(client_mail).to include(relabeled: true)
      expect(client_mail[:paths]).not_to eq([zip_path])
      expect(ExportDeliveryMailer).not_to have_received(:processing_alert_email).with(anything, anything, hash_including(original_sent: true))
    end

    it 'guarda una copia del zip original y la cita en el aviso (para reproducir el reclamo despues)' do
      allow(ExportRelabeling::EvidenceStore).to receive(:save).and_return('evidence/2026/11/16/p123456/excel_ab12_x.zip')
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call)
        .and_raise(ExportRelabeling::ConfirmitSchemaFetcher::PermissionDeniedError, 'Permission denied')

      described_class.new.perform(zip_path, 'p123456', recipients)

      expect(ExportRelabeling::EvidenceStore).to have_received(:save).with(hash_including(project_id: 'p123456', export_type: :excel))
      expect(ExportDeliveryMailer).to have_received(:processing_alert_email)
        .with(anything, 'p123456', hash_including(evidence: 'evidence/2026/11/16/p123456/excel_ab12_x.zip'))
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
  end
end
