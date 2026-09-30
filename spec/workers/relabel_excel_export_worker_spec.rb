# frozen_string_literal: true

require 'rails_helper'
require 'zip'
require 'rubyXL'
require 'tmpdir'

RSpec.describe RelabelExcelExportWorker do
  # Ver mismo comentario en relabel_spss_export_worker_spec.rb -- sin esto
  # cada test pegaria a la API real de Confirmit.
  before { allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(nil) }

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

  it 'extrae el zip, reescribe los encabezados en 3 filas, y manda el .xlsx resultante por mail' do
    # El worker borra su directorio de trabajo en el "ensure" apenas termina
    # perform -- hay que leer el archivo de salida DURANTE la llamada al
    # mailer (antes de que perform retorne), no despues.
    captured = {}
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |recipients, project_id, output_paths|
      captured[:recipients] = recipients
      captured[:project_id] = project_id
      captured[:output_paths] = output_paths
      captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(captured[:recipients]).to eq(['destino@cliente.com'])
    expect(captured[:project_id]).to eq('p123456')
    expect(captured[:output_paths].length).to eq(1)

    sheet = captured[:workbook].worksheets[0]
    expect(sheet.sheet_name).to eq('Sheet1')
    expect(sheet[0].cells.map(&:value)).to eq([nil, 'F4'])
    expect(sheet[1].cells.map(&:value)).to eq([nil, 'Consultório/Clínica/Hospital PRIVADO'])
    expect(sheet[2].cells.map(&:value)).to eq(['responseid', 'Dentre os locais?'])
    expect(sheet[3].cells.map(&:value)).to eq(%w[1 2])
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
      ['Variable', 'Code', 'Attribute', 'Question', 'Mean', 'Min', 'Max', 'Nulls', '% Nulls', 'Zeros', '', '',
       'Answer Options']
    )
    expect(dictionary[1].cells.map(&:value)).to eq(
      ['responseid', nil, nil, 'responseid', 2.0, 1.0, 3.0, 0, 0.0, 0, nil, nil, nil]
    )
    expect(dictionary[2].cells.map(&:value)).to eq(
      ['f4_1', 'F4', 'Consultório/Clínica/Hospital PRIVADO', 'Dentre os locais?', 1.0, 0.0, 2.0, 1, 33.33, 1, nil, nil, nil]
    )
  end

  it 'borra el zip original y el directorio de trabajo al terminar' do
    stub_mailer

    described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com'])

    expect(File.exist?(zip_path)).to be false
  end

  # Diego: "lo mas seguro seria que si algo falla se envie lo mismo que se
  # recibio... cubrimos el riesgo de que los datos se enviaron aunque el
  # formato no fuera perfecto". Si el pipeline CENTRAL revienta (no una
  # mejora opcional, ya cubiertas por #safely en otros tests), el worker
  # manda el zip original tal cual en vez de no mandar nada.
  it 'si el pipeline central revienta (ej. el Excel no se puede leer), manda el zip original sin cambios en vez de nada' do
    allow(ExportRelabeling::ExcelReader).to receive(:call).and_raise(StandardError, 'archivo corrupto')

    captured = {}
    allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths, relabeled: true|
      captured[:output_paths] = output_paths
      captured[:relabeled] = relabeled
      instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    end

    expect { described_class.new.perform(zip_path, 'p123456', ['destino@cliente.com']) }.not_to raise_error

    expect(captured[:output_paths]).to eq([zip_path])
    expect(captured[:relabeled]).to be false
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
      allow(lookup).to receive(:answer_options).and_return([])
      allow(lookup).to receive(:variable_type).with('s0').and_return('Single')
      allow(lookup).to receive(:quotas).and_return(
        [{ name: 'quota1', cells: [{ limit: 88, fields: [{ name: 's0', precode: nil, value: '1' }] }] }]
      )
      allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

      captured = {}
      allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
        captured[:workbook] = RubyXL::Parser.parse(output_paths.first)
        instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      end

      described_class.new.perform(zip_path_with_status, 'p123456', ['destino@cliente.com'])

      quotas_sheet = captured[:workbook].worksheets[2]
      expect(quotas_sheet.sheet_name).to eq('Quotas')
      expect(quotas_sheet[0].cells.map(&:value)).to eq(%w[Quota Variable Value Goal Achieved Pending])
      expect(quotas_sheet[0][0].is_bolded).to be true
      expect(quotas_sheet[0][0].fill_color).to eq('FFFF00')
      expect(quotas_sheet[1].cells.map(&:value)).to eq(['quota1', 's0', '1', 88, 2, 86])
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
      allow(lookup).to receive(:answer_options).and_return([])
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
      allow(lookup).to receive(:answer_options).and_return([])
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

      it 'resuelve "completa" buscando el label entre las respuestas, no asumiendo un precode fijo' do
        lookup = instance_double(ExportRelabeling::ConfirmitVariableLookup)
        allow(lookup).to receive(:call).and_return(nil)
        allow(lookup).to receive(:answer_options).and_return([])
        allow(lookup).to receive(:variable_type).with('qestado_1').and_return('Multi')
        allow(lookup).to receive(:answer_label_matching).with('fichaestado', %w[completa complete c]).and_return('completa')
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
        allow(lookup).to receive(:answer_options).and_return([])
        allow(lookup).to receive(:answer_label_matching).and_return('completa')
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
        allow(lookup).to receive(:answer_options).and_return([])
        allow(lookup).to receive(:variable_type).with('s0').and_return('Single')
        allow(lookup).to receive(:answer_label_matching).and_return('completa')
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
        allow(lookup).to receive(:answer_options).and_return([])
        allow(lookup).to receive(:answer_label_matching).and_return('completa')
        allow(lookup).to receive(:quotas).and_return([])
        allow(ExportRelabeling::ConfirmitSchemaFetcher).to receive(:call).and_return(lookup)

        captured = {}
        allow(ExportDeliveryMailer).to receive(:relabeled_export_email) do |_recipients, _project_id, output_paths|
          main_output = output_paths.find { |p| !p.include?('fichas') }
          captured[:workbook] = RubyXL::Parser.parse(main_output)
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
        allow(lookup).to receive(:answer_options).and_return([])
        allow(lookup).to receive(:answer_label_matching).and_return('completa')
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
end
