# frozen_string_literal: true

require 'rails_helper'
require 'zip'
require 'tmpdir'

RSpec.describe ExportRelabeling::ExcelReader do
  # Arma un .xlsx a mano, reproduciendo la forma exacta del XML real de
  # Confirmit: workbook.xml con el namespace principal CON prefijo ("x:"),
  # que es justo lo que rubyXL no puede parsear (confirmado contra
  # p573989981944_dcasar_585995116.xlsx) -- valida que Nokogiri +
  # remove_namespaces! no tiene ese problema.
  let(:xlsx_path) do
    dir = Dir.mktmpdir
    path = File.join(dir, 'confirmit_style.xlsx')

    workbook_xml = <<~XML
      <?xml version="1.0" encoding="utf-8"?><x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:sheets><x:sheet name="Sheet1" sheetId="1" r:id="RID1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" /></x:sheets></x:workbook>
    XML

    rels_xml = <<~XML
      <?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet.xml" Id="RID1" /></Relationships>
    XML

    # Fila de datos con un hueco a proposito (falta la celda "C2") para
    # validar que el alineado por referencia de columna (no por orden de
    # aparicion) deja el hueco como nil en vez de correr el resto de los
    # valores.
    sheet_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
      <row r="1"><c r="A1" t="str"><v>responseid</v></c><c r="B1" t="str"><v>f4_1 : Consultório/Clínica/Hospital PRIVADO (F4 - Dentre os locais de atendimento?)</v></c><c r="C1" t="str"><v>status</v></c></row>
      <row r="2"><c r="A2" t="str"><v>1</v></c><c r="C2" t="str"><v>Complete</v></c></row>
      </sheetData></worksheet>
    XML

    Zip::File.open(path, Zip::File::CREATE) do |zip|
      zip.get_output_stream('xl/workbook.xml') { |f| f.write(workbook_xml) }
      zip.get_output_stream('xl/_rels/workbook.xml.rels') { |f| f.write(rels_xml) }
      zip.get_output_stream('xl/worksheets/sheet.xml') { |f| f.write(sheet_xml) }
    end

    path
  end

  subject(:sheet) { described_class.call(xlsx_path) }

  it 'lee el nombre de hoja desde workbook.xml aunque use namespace con prefijo (el caso que rompe rubyXL)' do
    expect(sheet.name).to eq('Sheet1')
  end

  it 'separa cada header en variable_name y raw_label por " : "' do
    expect(sheet.headers[0]).to have_attributes(variable_name: 'responseid', raw_label: 'responseid')
    expect(sheet.headers[1]).to have_attributes(
      variable_name: 'f4_1',
      raw_label: 'Consultório/Clínica/Hospital PRIVADO (F4 - Dentre os locais de atendimento?)'
    )
  end

  it 'alinea las filas de datos por referencia de columna, dejando un nil en la celda faltante' do
    expect(sheet.rows).to eq([['1', nil, 'Complete']])
  end

  it 'no rompe ni detecta columnas de fecha cuando el .xlsx no trae styles.xml' do
    expect(sheet.date_columns).to eq([])
  end

  context 'cuando el .xlsx trae styles.xml con una columna en formato de fecha (ej. una pregunta tipo fecha, "Q11")' do
    let(:xlsx_path) do
      dir = Dir.mktmpdir
      path = File.join(dir, 'confirmit_dates.xlsx')

      workbook_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?><x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:sheets><x:sheet name="Sheet1" sheetId="1" r:id="RID1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" /></x:sheets></x:workbook>
      XML

      rels_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet.xml" Id="RID1" /></Relationships>
      XML

      # Mismos numFmtId reales confirmados contra el .xlsx de fichas de
      # Confirmit: id 14 (built-in, fecha) para la columna B, id custom
      # 164 "###0" (entero, NO es fecha) para la columna C -- valida que
      # solo la que realmente es fecha queda marcada.
      styles_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?><x:styleSheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:numFmts count="1"><x:numFmt numFmtId="164" formatCode="###0" /></x:numFmts><x:cellXfs count="3"><x:xf numFmtId="0" /><x:xf numFmtId="14" applyNumberFormat="1" /><x:xf numFmtId="164" applyNumberFormat="1" /></x:cellXfs></x:styleSheet>
      XML

      sheet_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        <row r="1"><c r="A1" t="str"><v>responseid</v></c><c r="B1" t="str"><v>q11 : Q11</v></c><c r="C1" t="str"><v>respid</v></c></row>
        <row r="2"><c r="A2" t="str"><v>1</v></c><c r="B2" s="1"><v>45847</v></c><c r="C2" s="2"><v>57</v></c></row>
        <row r="3"><c r="A3" t="str"><v>2</v></c><c r="B3" s="1"><v>45910</v></c><c r="C3" s="2"><v>58</v></c></row>
        </sheetData></worksheet>
      XML

      Zip::File.open(path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('xl/workbook.xml') { |f| f.write(workbook_xml) }
        zip.get_output_stream('xl/_rels/workbook.xml.rels') { |f| f.write(rels_xml) }
        zip.get_output_stream('xl/styles.xml') { |f| f.write(styles_xml) }
        zip.get_output_stream('xl/worksheets/sheet.xml') { |f| f.write(sheet_xml) }
      end

      path
    end

    it 'marca como columna de fecha solo la que usa el estilo con numFmtId de fecha (built-in 14), no la que usa un formato numerico custom' do
      expect(sheet.date_columns).to eq([1])
    end

    it 'no altera el valor crudo de la celda (sigue siendo el numero de serie de Excel como string)' do
      expect(sheet.rows.first[1]).to eq('45847')
    end
  end
end
