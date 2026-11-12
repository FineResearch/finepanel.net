# frozen_string_literal: true

# Deja el .asc/.dat de un export SPSS de Confirmit listo para que PSPP lo lea
# con el DATA LIST FIXED del .sps, sin que ninguna columna se corra.
#
# Dos cosas rompian la lectura de columnas, las dos porque PSPP cuenta por
# BYTE y Confirmit arma el archivo por CARACTER:
#
# 1. BOM UTF-8 (3 bytes invisibles al principio): corria TODA la primera
#    fila hacia la derecha (confirmado con p833174000229).
# 2. Caracteres con tilde (UTF-8 = 2 bytes cada uno) dentro de un texto
#    libre ("Outro. Especifique", etc.): cada tilde corria una posicion todo
#    lo que viene a la derecha en esa fila. Confirmado con p588393362171: el
#    cliente vio 5 casos con las columnas desplazadas desde D3_1 y T7, justo
#    despues de textos como "voce", "saude" o "Topicos".
#
# Para (2) el archivo se pasa de UTF-8 a Windows-1252 (1 byte por caracter,
# cubre portugues/espanol/ingles, el euro y las comillas tipograficas) y el
# .sps declara ese encoding en el FILE HANDLE (ver #encoding): PSPP lo lee
# 1 byte = 1 columna y guarda el .sav igual en UTF-8. Un caracter que
# Windows-1252 no tiene (otro alfabeto, emojis) se reemplaza por un unico "?":
# se pierde ese caracter pero ninguna columna se corre.
#
# No se toca el archivo ORIGINAL (el fallback a "se manda la base sin
# cambios" usa el zip tal cual llego) -- si hay algo que cambiar, se escribe
# una copia al lado.
module ExportRelabeling
  class SpssDataFilePreparer
    UTF8_BOM = "\xEF\xBB\xBF".b.freeze
    ENCODING = 'Windows-1252'

    # encoding: nil si el archivo se compila tal cual (lo que el .sps declare
    # por default), o el nombre que hay que declarar en el FILE HANDLE.
    Result = Struct.new(:path, :encoding)

    def self.call(data_path)
      new(data_path).call
    end

    def initialize(data_path)
      @data_path = data_path
    end

    def call
      content = File.read(@data_path, mode: 'rb')
      had_bom = content.start_with?(UTF8_BOM)
      content = content.byteslice(UTF8_BOM.bytesize..-1) if had_bom

      text = content.dup.force_encoding(Encoding::UTF_8)
      # Un archivo que no es UTF-8 valido (ya viene en una pagina de codigos de
      # 1 byte, o esta danado) no se transcodifica: no se sabe que son esos bytes.
      return write_copy(transcode(text), ENCODING) if text.valid_encoding? && !content.ascii_only?
      return write_copy(content, nil) if had_bom

      Result.new(@data_path, nil)
    end

    private

    def transcode(text)
      transcoded = text.encode(ENCODING, Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?').b
      replaced = transcoded.count('?') - text.count('?')
      Rails.logger.warn("[SpssDataFilePreparer] #{replaced} caracter(es) sin equivalente en #{ENCODING} reemplazados por '?' en #{File.basename(@data_path)}") if replaced.positive?
      transcoded
    end

    def write_copy(content, encoding)
      path = @data_path.sub(/(\.[^.\/]+)\z/, '_pspp\1')
      File.write(path, content, mode: 'wb')
      Result.new(path, encoding)
    end
  end
end
