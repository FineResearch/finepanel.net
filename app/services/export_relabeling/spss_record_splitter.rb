# frozen_string_literal: true

# PSPP lee MAL las columnas de un DATA LIST FIXED que pasan de la 65535: les da la vuelta (modulo
# 65536) y la variable se llena con el contenido de otra columna mas a la izquierda, sin ningun
# aviso. Pasa con los exports de Confirmit con muchos campos de texto abiertos de 4000 caracteres
# (los "_OTHER"), cuya linea mide 100 a 300 mil bytes: p215401338743, p899583054321, p330455179161.
# Ej. confirmado: AW2B_1 (columnas 68454-72453) traia el contenido de LINKFARMACO (4037-8036),
# porque 68454 - 65536 = 2918 y 2918 + 1119 = 4037. SavVerifier lo detecta (por eso esos exports
# salieron SIN relabellear), pero la causa esta en PSPP, no en los datos ni en el verificador.
#
# Solucion: cuando alguna columna pasa del limite, cada linea del archivo de datos se parte en
# varios registros ("RECORDS=n", "/1", "/2"...) de a lo sumo MAX_RECORD_BYTES, cortando siempre entre
# una variable y la siguiente, y las columnas de cada registro se reubican desde 1. PSPP no deja
# volver a un registro anterior, asi que las variables salen agrupadas por registro: el orden del
# cuestionario se restituye con /KEEP en el SAVE (ver Result#keep_clause).
#
# Si el export no pasa del limite, el texto y el archivo salen tal cual (nada cambia para los
# exports que ya funcionan). Si el DATA LIST no tiene la forma esperada, tambien se deja igual:
# SavVerifier es la red de seguridad, y un .sav mal armado se entrega como original.
module ExportRelabeling
  class SpssRecordSplitter
    COLUMN_LIMIT = 65_535
    MAX_RECORD_BYTES = 60_000
    KEEP_NAMES_PER_LINE = 12

    # keep_clause: texto para agregar al SAVE (" /KEEP=..."), vacio si no se partio nada.
    Result = Struct.new(:sps_text, :data_path, :keep_clause, :split) do
      def split?
        split
      end
    end

    Column = Struct.new(:line_index, :name, :start, :finish, :format)

    def self.call(sps_text:, data_path:)
      new(sps_text, data_path).call
    end

    def initialize(sps_text, data_path)
      @text = sps_text
      @data_path = data_path
    end

    def call
      lines = @text.each_line.to_a
      block = locate_block(lines)
      return unchanged unless block

      columns = block[:columns]
      return unchanged if columns.empty? || columns.map(&:finish).max <= COLUMN_LIMIT

      chunks = plan_chunks(columns)
      return unchanged unless chunks

      new_text = rewrite_sps(lines, block, columns, chunks)
      split_path = split_data(chunks)
      Rails.logger.info("[SpssRecordSplitter] columnas hasta #{columns.map(&:finish).max}: el DATA LIST se parte en #{chunks.length} registros de a lo sumo #{MAX_RECORD_BYTES} bytes")
      Result.new(new_text, split_path, keep_clause(columns), true)
    rescue StandardError => e
      Rails.logger.error("[SpssRecordSplitter] no se pudo partir el DATA LIST, se deja como esta: #{e.class} #{e.message}")
      unchanged
    end

    private

    def unchanged
      Result.new(@text, @data_path, '', false)
    end

    # Primer bloque DATA LIST con el formato de Confirmit (un solo registro "/1"). Devuelve nil si
    # tiene otra forma (mas de un registro, sin variables) para no tocarlo.
    def locate_block(lines)
      start = lines.index { |line| line.strip.match?(SpssDataListReader::DATA_LIST_START) }
      return unless start

      finish = ((start + 1)...lines.length).find { |index| lines[index].strip.match?(SpssDataListReader::BLOCK_END) }
      return unless finish

      markers = ((start + 1)...finish).select { |index| lines[index].strip.match?(SpssDataListReader::RECORD_MARKER) }
      return unless markers.length == 1 && lines[markers.first].strip == '/1'

      columns = ((markers.first + 1)...finish).map { |index| column_for(lines, index) }.compact
      { start: start, marker: markers.first, finish: finish, columns: columns }
    end

    def column_for(lines, index)
      match = SpssDataListReader::VARIABLE_DEF.match(lines[index].strip)
      return unless match

      Column.new(index, match[1], match[2].to_i, (match[3] || match[2]).to_i, match[4])
    end

    # [[inicio, fin], ...] en columnas del archivo original (1-indexadas e inclusivas): cada registro
    # arranca donde arranca una variable y la ultima variable que entra termina dentro del tope.
    def plan_chunks(columns)
      sorted = columns.sort_by(&:start)
      return if sorted.any? { |column| column.finish - column.start + 1 > MAX_RECORD_BYTES }

      starts = [1]
      sorted.each do |column|
        starts << column.start if column.finish - starts.last + 1 > MAX_RECORD_BYTES && column.start > starts.last
      end
      total = sorted.map(&:finish).max
      chunks = starts.each_with_index.map { |from, index| [from, (starts[index + 1] || (total + 1)) - 1] }
      # una variable que cruza el limite de su registro (columnas superpuestas) -> no se sabe partir
      return if sorted.any? { |column| chunk = chunk_for(chunks, column); column.finish > chunk.last }

      chunks
    end

    def chunk_for(chunks, column)
      chunks.reverse_each.find { |from, _to| from <= column.start }
    end

    def rewrite_sps(lines, block, columns, chunks)
      eol = lines[block[:marker]][/\r?\n\z/] || "\n"
      by_record = columns.group_by { |column| chunks.index(chunk_for(chunks, column)) }

      body = chunks.each_index.flat_map do |record|
        shift = chunks[record].first - 1
        ["/#{record + 1}#{eol}"] + by_record.fetch(record, []).map { |column| definition(column, shift, eol) }
      end

      output = lines.dup
      output[block[:marker]..(block[:finish] - 1)] = body
      widest = chunks.map { |from, to| to - from + 1 }.max
      # solo el encabezado (FILE HANDLE ... /LRECL y DATA LIST ... RECORDS): el resto de la sintaxis no se toca
      header = (0...block[:marker]).map do |index|
        output[index].sub(/\bRECORDS\s*=\s*\d+/i, "RECORDS=#{chunks.length}").sub(%r{/LRECL\s*=\s*\d+}i, "/LRECL=#{widest}")
      end
      (header + output[block[:marker]..-1]).join
    end

    def definition(column, shift, eol)
      from = column.start - shift
      to = column.finish - shift
      span = column.start == column.finish ? from.to_s : "#{from}-#{to}"
      " #{column.name} #{span}#{column.format ? " (#{column.format})" : ''}#{eol}"
    end

    # El orden final de las variables es el del DATA LIST original (ya ordenado segun el cuestionario).
    def keep_clause(columns)
      rows = columns.map(&:name).each_slice(KEEP_NAMES_PER_LINE).map { |names| " #{names.join(' ')}" }
      " /KEEP=\n#{rows.join("\n")}"
    end

    # Copia del archivo de datos con una linea por registro; cada linea original se completa con
    # espacios hasta el ancho total (Confirmit a veces recorta los espacios finales) antes de cortarla.
    def split_data(chunks)
      total = chunks.last.last
      path = @data_path.sub(/(\.[^.\/]+)\z/, '_split\1')
      File.open(path, 'wb') do |out|
        File.foreach(@data_path, mode: 'rb') do |raw|
          line = raw.chomp("\n").chomp("\r").b
          line = line.ljust(total, ' ') if line.bytesize < total
          chunks.each { |from, to| out.write(line.byteslice(from - 1, to - from + 1), "\n") }
        end
      end
      path
    end
  end
end
