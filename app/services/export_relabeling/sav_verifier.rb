# frozen_string_literal: true

# Verifica que el .sav que compilo PSPP tenga los MISMOS datos que el .dat original
# de Confirmit, leido por las columnas del DATA LIST (caracter por caracter, que es
# como Confirmit define las columnas). Un .sav con las columnas desplazadas -- el
# reclamo de FP-18810G: "T7_99_OTHER" con la fecha de fin de la entrevista, "T8A_99_OTHER"
# con "1AC" (p3 + p4_1) -- se entregaba sin que nadie lo notara. Ahora levanta
# MismatchError y el worker retiene el export con un aviso.
#
# Compara hasta SAMPLE_ROWS casos repartidos en todo el archivo (todos si son menos).
# La verificacion es de mejor esfuerzo SOLO en lo que no puede asegurar: si el .sav usa
# un formato que SavReader no soporta, o algo falla leyendo, levanta otro error y el
# worker entrega sin verificar. Una diferencia real siempre levanta MismatchError.
module ExportRelabeling
  class SavVerifier
    class MismatchError < StandardError; end

    # No se pudo verificar (formato no soportado, variables que no coinciden en cantidad...):
    # no es un fallo del .sav.
    class UnverifiableError < StandardError; end

    SAMPLE_ROWS = 2000
    # Un desfasaje real rompe cientos de celdas por fila; un redondeo o un texto truncado, casi
    # ninguna. 0,2% deja pasar lo segundo y detecta hasta UN registro desplazado de ~270.
    MAX_MISMATCH_RATIO = 0.002
    NUMERIC_TOLERANCE = 1e-9
    UTF8_BOM = "\xEF\xBB\xBF".b.freeze
    WORST_COLUMNS_LISTED = 6

    def self.call(sav_path:, sps_text:, data_path:)
      new(sav_path, sps_text, data_path).call
    end

    def initialize(sav_path, sps_text, data_path)
      @sav_path = sav_path
      @columns = SpssDataListReader.columns(sps_text)
      @data_path = data_path
    end

    def call
      raise UnverifiableError, 'el .sps no tiene columnas en el DATA LIST' if @columns.empty?

      reader = SavReader.new(@sav_path).dictionary
      check_variables(reader)
      lines = data_line_count
      step = [lines / SAMPLE_ROWS, 1].max
      stats = { cells: 0, rows: 0, mismatches: Hash.new(0), examples: {} }

      sav_cases = 0
      sampled = ->(index) { (index % step).zero? || index == lines - 1 }
      File.open(@data_path, 'rb') do |io|
        reader.each_case(sample: sampled) do |index, values|
          sav_cases += 1
          line = io.gets
          next if line.nil? || values.nil?

          compare_row(index, strip_bom(line, index), values, stats)
        end
      end
      raise MismatchError, "el .sav tiene #{sav_cases} casos y el .dat #{lines}" unless sav_cases == lines

      finish(stats, lines)
    rescue SavReader::UnsupportedFormat => e
      raise UnverifiableError, e.message
    end

    private

    def check_variables(reader)
      return if reader.variables.length == @columns.length

      raise UnverifiableError, "el .sav tiene #{reader.variables.length} variables y el DATA LIST #{@columns.length}"
    end

    # Lineas con datos: las vacias del final (el salto de linea de cierre) no cuentan.
    def data_line_count
      count = 0
      blank_run = 0
      File.foreach(@data_path, mode: 'rb') do |line|
        if line.strip.empty?
          blank_run += 1
        else
          count += blank_run + 1
          blank_run = 0
        end
      end
      count
    end

    def strip_bom(line, index)
      index.zero? && line.start_with?(UTF8_BOM) ? line.byteslice(UTF8_BOM.bytesize..-1) : line
    end

    def compare_row(index, line, values, stats)
      text = decode(line.chomp)
      # Cortar por caracter un texto con tildes es O(largo) por cada columna: se pasa a codepoints una vez.
      codepoints = text.ascii_only? ? nil : text.unpack('U*')
      stats[:rows] += 1
      @columns.each_with_index do |column, position|
        stats[:cells] += 1
        expected = slice(text, codepoints, column)
        next if equal_cell?(column, expected, values[position])

        stats[:mismatches][column[:name]] += 1
        stats[:examples][column[:name]] ||= [index + 1, expected.strip[0, 30], values[position].inspect[0, 30]]
      end
    end

    def slice(text, codepoints, column)
      from = column[:start] - 1
      return text[from...column[:end]].to_s unless codepoints

      (codepoints[from...column[:end]] || []).pack('U*')
    end

    # El .dat de Confirmit es UTF-8; si no lo fuera (un solo byte invalido), se lee como
    # Windows-1252 para no romper la comparacion.
    def decode(bytes)
      utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
      return utf8 if utf8.valid_encoding?

      bytes.dup.force_encoding('Windows-1252').encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
    end

    def equal_cell?(column, expected, actual)
      string_column?(column) ? equal_string?(expected, actual) : equal_number?(column, expected, actual)
    end

    def string_column?(column)
      column[:format].to_s.upcase.start_with?('A')
    end

    # Con decimales implicitos ("X 1-5 (2)") el .dat trae "00123" y el valor es 1,23, salvo que ya
    # traiga el punto decimal.
    def equal_number?(column, expected, actual)
      value = parse_number(expected, column[:format])
      return actual.nil? if value.nil?
      return false if actual.nil?

      (value - actual).abs <= NUMERIC_TOLERANCE * [1.0, value.abs].max
    end

    def parse_number(text, format)
      stripped = text.strip
      return nil if stripped.empty?

      number = Float(stripped)
      format.to_s.match?(/\A\d+\z/) && !stripped.include?('.') ? number / (10**format.to_i) : number
    rescue ArgumentError
      nil
    end

    # El .sav guarda el texto en UTF-8 con el MISMO ancho en BYTES que el .dat en caracteres,
    # asi que un texto con tildes puede quedar cortado al final: se acepta que lo guardado sea
    # un prefijo de lo esperado. Un caracter que Windows-1252 no tiene se guarda como "?".
    def equal_string?(expected, actual)
      actual = actual.to_s.dup.force_encoding(Encoding::UTF_8).scrub('').rstrip
      wanted = expected.rstrip
      return true if wanted.start_with?(actual)

      wanted.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '?').encode(Encoding::UTF_8).start_with?(actual)
    end

    def finish(stats, lines)
      mismatched = stats[:mismatches].values.sum
      ratio = stats[:cells].zero? ? 0.0 : mismatched.fdiv(stats[:cells])
      summary = { cases: lines, rows: stats[:rows], cells: stats[:cells], mismatched_cells: mismatched, ratio: ratio }
      raise MismatchError, mismatch_message(stats, mismatched, lines) if ratio > MAX_MISMATCH_RATIO

      summary
    end

    def mismatch_message(stats, mismatched, lines)
      worst = stats[:mismatches].sort_by { |_name, count| -count }.first(WORST_COLUMNS_LISTED).map do |name, count|
        row, expected, got = stats[:examples][name]
        "#{name} (#{count} filas; ej. fila #{row}: esperado #{expected.inspect}, obtuvo #{got})"
      end
      "#{mismatched} de #{stats[:cells]} celdas verificadas (#{stats[:rows]} de #{lines} casos) no coinciden con el .dat. " \
        "#{stats[:mismatches].length} variable(s) afectadas: #{worst.join('; ')}"
    end
  end
end
