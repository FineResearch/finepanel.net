# frozen_string_literal: true

require 'rails_helper'
require 'rubyXL'
require 'tmpdir'
require 'zip'

RSpec.describe ExportRelabeling::ExcelWriter do
  it 'escribe la hoja principal con 3 filas de encabezado y los datos debajo, legible por rubyXL' do
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.xlsx')

      described_class.call(
        sheet_name: 'Sheet1',
        header_rows: [%w[F4 respondent_id], ['Consultório/Clínica/Hospital PRIVADO', nil], ['Dentre os locais...', nil]],
        data_rows: [['1', '100'], ['2', '101']],
        output_path: output_path
      )

      workbook = RubyXL::Parser.parse(output_path)
      sheet = workbook.worksheets[0]

      expect(sheet.sheet_name).to eq('Sheet1')
      expect(sheet[0].cells.map(&:value)).to eq(%w[F4 respondent_id])
      expect(sheet[1].cells.map(&:value)).to eq(['Consultório/Clínica/Hospital PRIVADO', nil])
      expect(sheet[3].cells.map(&:value)).to eq(%w[1 100])
      expect(sheet[4].cells.map(&:value)).to eq(%w[2 101])
    end
  end

  it 'agrega una hoja extra por cada entrada de extra_sheets, en orden' do
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.xlsx')

      described_class.call(
        sheet_name: 'Sheet1',
        header_rows: [['Q1']],
        data_rows: [['a']],
        extra_sheets: {
          'Diccionario' => [%w[Variable Pregunta], ['q1', 'Texto de la pregunta']],
          'Cuotas' => [%w[Cota Meta], ['quota1', '180']]
        },
        output_path: output_path
      )

      workbook = RubyXL::Parser.parse(output_path)

      expect(workbook.worksheets.map(&:sheet_name)).to eq(%w[Sheet1 Diccionario Cuotas])
      dictionary_sheet = workbook.worksheets[1]
      expect(dictionary_sheet[0].cells.map(&:value)).to eq(%w[Variable Pregunta])
      expect(dictionary_sheet[1].cells.map(&:value)).to eq(['q1', 'Texto de la pregunta'])
      quotas_sheet = workbook.worksheets[2]
      expect(quotas_sheet[0].cells.map(&:value)).to eq(%w[Cota Meta])
    end
  end

  it 'no agrega hojas extra si no se pasa extra_sheets, o si vienen vacias' do
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.xlsx')

      described_class.call(
        sheet_name: 'Sheet1',
        header_rows: [['Q1']],
        data_rows: [['a']],
        extra_sheets: { 'Cuotas' => [] },
        output_path: output_path
      )

      workbook = RubyXL::Parser.parse(output_path)
      expect(workbook.worksheets.length).to eq(1)
    end
  end

  it 'resalta en negrita y fondo amarillo las filas indicadas via highlighted_rows' do
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.xlsx')

      described_class.call(
        sheet_name: 'Sheet1',
        header_rows: [['Q1']],
        data_rows: [['a']],
        extra_sheets: {
          'Quotas' => { rows: [%w[Quota Variable], %w[q1 s0], %w[q2 s1]], highlighted_rows: [0] }
        },
        output_path: output_path
      )

      sheet = RubyXL::Parser.parse(output_path).worksheets[1]

      expect(sheet[0][0].is_bolded).to be true
      expect(sheet[0][1].is_bolded).to be true
      expect(sheet[0][0].fill_color).to eq('FFFF00')
      expect(sheet[1][0].is_bolded).to be_falsey
    end
  end

  it 'aplica formato de fecha a las columnas indicadas en date_columns, sin tocar el valor crudo' do
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.xlsx')

      described_class.call(
        sheet_name: 'Sheet1',
        header_rows: [%w[Q11 responseid]],
        data_rows: [%w[45847 1], %w[45910 2]],
        date_columns: [0],
        output_path: output_path
      )

      sheet = RubyXL::Parser.parse(output_path).worksheets[0]

      # rubyXL detecta que la celda es numerica + formato de fecha y la
      # devuelve como fecha/hora real -- justamente la prueba de que quedo
      # bien escrita (con el bug viejo, .value devolvia el string crudo).
      expect(sheet[1][0].value).to respond_to(:strftime)
      expect(sheet[1][0].value.strftime('%Y-%m-%d')).to eq('2025-07-09')
      expect(sheet[1][0].is_date?).to be true
      expect(sheet[2][0].is_date?).to be true
      expect(sheet[1][1].is_date?).to be_falsey
    end
  end

  # rubyXL#is_date? solo mira el estilo y el patron numerico del valor, sin
  # importar si la celda quedo tipada como texto -- eso llevo a un bug real
  # (confirmado con un archivo real de Confirmit): el estilo de fecha
  # quedaba bien aplicado pero la celda seguia mostrando el numero crudo en
  # Excel, porque el TIPO de la celda era texto (t="str") y Excel nunca le
  # aplica formato de numero/fecha a una celda de texto, sin importar el
  # estilo. Se valida contra el XML crudo del .xlsx, no via rubyXL, para no
  # repetir el mismo punto ciego.
  it 'escribe el valor de una columna de fecha como NUMERO, no como texto (si no, Excel ignora el formato)' do
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.xlsx')

      described_class.call(
        sheet_name: 'Sheet1',
        header_rows: [['Q11']],
        data_rows: [['45847']],
        date_columns: [0],
        output_path: output_path
      )

      raw_sheet_xml = Zip::File.open(output_path) { |zip| zip.read('xl/worksheets/sheet1.xml') }
      data_cell = raw_sheet_xml[/<c r="A2"[^>]*>.*?<\/c>/]

      expect(data_cell).not_to include('t="str"')
      expect(data_cell).to include('<v>45847</v>')
    end
  end
end
