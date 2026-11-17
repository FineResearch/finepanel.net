# frozen_string_literal: true

# Lector minimo de archivos .sav (SPSS system file) -- solo lo que hace falta para
# VERIFICAR el .sav que compila PSPP contra el .dat original (ver SavVerifier).
# Soporta lo que escribe PSPP: little-endian, sin compresion o con compresion
# "bytecode" (la default), incluidas las cadenas de mas de 255 bytes ("very long strings").
# Lo demas (zlib, big-endian) levanta UnsupportedFormat y la verificacion se omite en
# vez de dar un falso resultado.
#
# Formato (https://www.gnu.org/software/pspp/pspp-dev/html_node/System-File-Format.html):
#   - cabecera de 176 bytes
#   - registros: 2 variable, 3+4 value labels, 6 documentos, 7 info, 999 fin del diccionario
#   - datos: cada caso son `nominal_case_size` "slots" de 8 bytes (un numero, o 8 bytes
#     de una cadena; una cadena de ancho w ocupa ceil(w/8) slots).
#   - una cadena de mas de 255 bytes (los campos "otro" de Confirmit, A4000) se guarda como
#     varias variables "segmento": todos menos el ultimo de 255 de ancho (32 slots) y el ultimo
#     con el resto. El registro de info 14 dice el ancho real; aca se vuelven a juntar,
#     tomando de cada segmento tantos bytes como su ancho declarado, hasta completar ese ancho.
module ExportRelabeling
  class SavReader
    class UnsupportedFormat < StandardError; end

    # segments: nil, o [[slots, bytes_utiles], ...] para una cadena muy larga ya reunida.
    Variable = Struct.new(:short_name, :name, :width, :segments) do
      def string?
        width.positive?
      end

      def slots
        return segments.sum(&:first) if segments

        string? ? (width + 7) / 8 : 1
      end
    end


    SYSMIS = -Float::MAX
    LONG_NAMES_SUBTYPE = 13
    VERY_LONG_STRINGS_SUBTYPE = 14

    attr_reader :variables, :case_count

    def initialize(path)
      @path = path
    end

    # Lee el diccionario (variables) sin recorrer los datos.
    def dictionary
      File.open(@path, 'rb') { |io| read_dictionary(io) }
      self
    end

    # Recorre los casos: yield(indice, valores). Numeros -> Float (nil si es perdido),
    # cadenas -> String binaria sin los espacios del final. Con `sample` (un proc que recibe el
    # indice y dice si interesa ese caso) los demas se recorren igual -- el flujo comprimido hay que
    # leerlo entero -- pero sin armarlos: yield(indice, nil). Con 40 mil casos de ~500 variables
    # armar todos es lo que mas tarda.
    def each_case(sample: nil)
      File.open(@path, 'rb') do |io|
        read_dictionary(io)
        index = 0
        each_slot_group(io, sample) do |slots|
          yield index, (slots && assemble(slots))
          index += 1
        end
      end
    end

    private

    def read_dictionary(io)
      header = io.read(176)
      raise UnsupportedFormat, 'no es un .sav' unless header && header.bytesize == 176 && header[0, 4] == '$FL2'

      layout = header[64, 4].unpack('l<').first
      raise UnsupportedFormat, "layout #{layout} (big-endian)" unless [2, 3].include?(layout)

      @slots_per_case = header[68, 4].unpack('l<').first
      @compression = header[72, 4].unpack('l<').first
      @case_count = header[80, 4].unpack('l<').first
      @bias = header[84, 8].unpack('E').first
      raise UnsupportedFormat, "compresion #{@compression}" unless [0, 1].include?(@compression)

      @variables = []
      @long_names = {}
      @very_long_strings = {}
      read_records(io)
      apply_long_names
    end

    def read_records(io)
      loop do
        record = int32(io)
        case record
        when 2 then read_variable(io)
        when 3 then skip_value_labels(io)
        when 6 then io.read(80 * int32(io))
        when 7 then read_info(io)
        when 999
          int32(io)
          return
        else raise UnsupportedFormat, "registro #{record.inspect}"
        end
      end
    end

    def read_variable(io)
      type, has_label, missing, = Array.new(5) { int32(io) }
      name = io.read(8).to_s.strip
      if has_label.positive?
        length = int32(io)
        io.read((length + 3) / 4 * 4)
      end
      io.read(8 * missing.abs) if missing != 0
      return if type == -1 # continuacion de una cadena ancha

      @variables << Variable.new(name, name, type, nil)
    end

    # Value labels: pares valor/etiqueta y, justo despues, el registro 4 con sus variables.
    def skip_value_labels(io)
      int32(io).times do
        io.read(8)
        length = io.read(1).unpack('C').first
        io.read((length + 1 + 7) / 8 * 8 - 1)
      end
      raise UnsupportedFormat, 'value labels sin registro 4' unless int32(io) == 4

      io.read(4 * int32(io))
    end

    def read_info(io)
      subtype = int32(io)
      size = int32(io)
      count = int32(io)
      data = io.read(size * count).to_s
      parse_long_names(data) if subtype == LONG_NAMES_SUBTYPE
      parse_very_long_strings(data) if subtype == VERY_LONG_STRINGS_SUBTYPE
    end

    # Pares NOMBRE=ancho separados por tab (cada uno termina en un NUL): el ancho real de cada cadena de mas de 255 bytes.
    def parse_very_long_strings(data)
      data.split("\t").each do |pair|
        name, width = pair.delete("\0").split('=', 2)
        @very_long_strings[name.strip.upcase] = width.to_i if name && width
      end
    end

    def parse_long_names(data)
      data.force_encoding(Encoding::UTF_8).split("\t").each do |pair|
        short, long = pair.split('=', 2)
        @long_names[short.strip.upcase] = long.to_s.strip if short && long
      end
    end

    def apply_long_names
      @variables.each { |variable| variable.name = @long_names.fetch(variable.short_name.upcase, variable.short_name) }
      expected = @variables.sum(&:slots)
      raise UnsupportedFormat, "slots #{expected} != #{@slots_per_case}" unless expected == @slots_per_case

      merge_very_long_strings
    end

    # Junta los segmentos de cada cadena muy larga en UNA variable. El registro 14 trae el nombre
    # corto del primer segmento y el ancho real; los segmentos siguientes son las variables que le
    # siguen, hasta cubrir ese ancho.
    def merge_very_long_strings
      return if @very_long_strings.empty?

      merged = []
      index = 0
      while index < @variables.length
        variable = @variables[index]
        width = @very_long_strings[variable.short_name.upcase]
        if width && width > 255
          segments = collect_segments(index, width)
          merged << Variable.new(variable.short_name, variable.name, width, segments)
          index += segments.length
        else
          merged << variable
          index += 1
        end
      end
      @variables = merged
    end

    # [[slots, bytes_utiles], ...] de los segmentos que arrancan en la variable `start`: de cada uno
    # cuentan tantos bytes como su ancho declarado (255, y el resto en el ultimo), hasta completar `width`.
    def collect_segments(start, width)
      remaining = width
      segments = []
      position = start
      while remaining.positive?
        segment = @variables[position]
        raise UnsupportedFormat, "segmentos de #{@variables[start].name}" if segment.nil? || !segment.string?

        useful = [segment.width, remaining].min
        segments << [segment.slots, useful]
        remaining -= useful
        position += 1
      end
      segments
    end

    # Agrupa los slots de datos de a un caso (nil si el caso no interesa, ver #each_case).
    def each_slot_group(io, sample)
      index = 0
      current = []
      taken = 0
      keep = sample.nil? || sample.call(0)
      each_slot(io) do |slot|
        current << slot if keep
        taken += 1
        next unless taken == @slots_per_case

        yield(keep ? current : nil)
        index += 1
        taken = 0
        current = []
        keep = sample.nil? || sample.call(index)
      end
    end

    # Cada slot: [:raw, 8 bytes] | [:spaces] | [:sysmis] | [:small, Float]
    def each_slot(io)
      return each_raw_slot(io) { |slot| yield slot } if @compression.zero?

      loop do
        commands = io.read(8)
        return if commands.nil? || commands.bytesize < 8

        commands.each_byte do |code|
          case code
          when 0 then next
          when 252 then return
          when 253 then yield [:raw, io.read(8)]
          when 254 then yield [:spaces]
          when 255 then yield [:sysmis]
          else yield [:small, code - @bias]
          end
        end
      end
    end

    def each_raw_slot(io)
      while (raw = io.read(8)) && raw.bytesize == 8
        yield [:raw, raw]
      end
    end

    def assemble(slots)
      position = 0
      @variables.map do |variable|
        taken = slots[position, variable.slots]
        position += variable.slots
        if variable.segments then very_long_string_value(taken, variable.segments)
        elsif variable.string? then string_value(taken, variable.width)
        else numeric_value(taken.first)
        end
      end
    end

    def numeric_value(slot)
      case slot[0]
      when :small then slot[1]
      when :raw
        value = slot[1].unpack('E').first
        value == SYSMIS ? nil : value
      end
    end

    def string_value(slots, width)
      bytes = slot_bytes(slots)
      bytes.byteslice(0, width).to_s.sub(/ +\z/, '')
    end

    # Cada segmento ocupa sus slots pero solo cuentan los primeros `useful` bytes.
    def very_long_string_value(slots, segments)
      position = 0
      text = segments.map do |slot_count, useful|
        piece = slot_bytes(slots[position, slot_count]).byteslice(0, useful).to_s
        position += slot_count
        piece
      end.join
      text.sub(/ +\z/, '')
    end

    def slot_bytes(slots)
      slots.map do |slot|
        case slot[0]
        when :raw then slot[1]
        when :spaces then ' ' * 8
        else raise UnsupportedFormat, 'slot no valido para una cadena'
        end
      end.join
    end

    def int32(io)
      data = io.read(4)
      raise UnsupportedFormat, 'archivo cortado' unless data && data.bytesize == 4

      data.unpack('l<').first
    end
  end
end
