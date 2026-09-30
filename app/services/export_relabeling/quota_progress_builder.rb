# frozen_string_literal: true

# Arma la hoja "Quotas" (progreso de campo) cruzando las cuotas definidas en
# Confirmit (ver ConfirmitVariableLookup#quotas) contra los datos YA
# exportados -- no confia en el contador de Confirmit (Diego: "a veces
# confirmit no es exacto consistente con la base"), cuenta directo de la
# misma planilla que se le manda al cliente.
#
# El criterio de que archivo usar para contar una celda es uno solo,
# validado con el usuario (no el limite repetido, que puede coincidir por
# casualidad -- ej. una cuota real de 50/50 hombres/mujeres -- sin ser una
# cuota de loop): la variable del QuotaField, ¿vive en el archivo de loop
# (ej. fichas) o fuera de el?
#
# - Fuera del loop: cada QuotaLimit es su propia fila/target independiente
#   -- ej. "distribucion_A" con 6 valores son 6 metas reales de 95 cada una,
#   no una sola meta repetida.
# - Dentro del loop: las celdas que comparten el mismo campo se COLAPSAN en
#   una sola fila -- confirmado con el usuario que la meta real es siempre
#   la de la PRIMERA linea del grupo (no hace falta que las demas coincidan
#   para confiar en ese valor), y el "conseguido" cuenta fichas donde ese
#   campo tenga CUALQUIERA de los valores del grupo (ej. "qestado_1" con
#   Value=1..4 representa una sola meta de fichas, no 4 metas de 34).
#
# Una celda puede tener mas de un QuotaField (cuota cruzada, ej.
# "hidden_s132=1 AND s0=2") -- confirmado con un caso real armado a
# proposito por el usuario (p314244165357, quota4): sin <Precode>, cada
# QuotaField trae solo Name+Value. Se cuenta con un AND entre todos los
# campos, siempre que TODOS vivan en el mismo archivo -- si estan repartidos
# entre el archivo principal y el de loop, no hay una fila comun que
# cruzarlos (una fila de loop no tiene 1:1 con un entrevistado), asi que se
# marca para revisar a mano en vez de adivinar.
#
# El <Value> de un QuotaField es el PRECODE, pero la columna exportada no
# siempre trae el precode -- confirmado contra un export real
# (p314244165357) que el Data Template exporta el TEXTO de la respuesta
# ("MSD", "Região Sudeste"), no el numero ("1", "2"). Por eso se
# matchea/muestra `field[:label] || field[:value]` (ver
# ConfirmitVariableLookup#quotas, que ya trae el label resuelto), nunca el
# precode crudo solo.
#
# Confirmado tambien contra un proyecto real (p573989981944) que una
# variable de cuota puede ser "VariableType=Hidden" en Confirmit -- esas
# nunca se incluyen en el Data Template exportado al cliente, asi que es
# imposible calcular su progreso desde el Excel (solo Confirmit mismo tiene
# ese dato). Por eso, ANTES de armar las filas de una Quota, se chequea que
# TODAS las variables que referencia (en cualquiera de sus celdas) existan
# en algun archivo -- si falta una sola, se excluye el reporte de ESA
# QUOTA COMPLETA (no solo la celda afectada): mostrar progreso parcial
# (algunas celdas si, otras "not found") daria una idea enganosa de cuanto
# esta realmente cubierto.
#
# Las cuotas de tipo Grid (fichas/loop, ej. "qregion", "distribucion") se
# excluyen ANTES de llegar a este servicio -- ver
# RelabelExcelExportWorker#exclude_grid_quotas -- porque conteo interno de
# Confirmit para ese tipo de variable no es confiable ni reproducible desde
# el export. Este servicio no vuelve a filtrar por tipo, asume que ya le
# llegan solo las cuotas a nivel de medico.
#
# El header de la tabla (ver HEADER) se repite en negrita + fondo amarillo
# al principio de CADA bloque de cuota (a pedido de Diego, para que cada
# tabla se lea sola sin tener que scrollear hasta arriba) -- por eso #call
# devuelve { rows:, header_indices: } en vez de un array plano: header_indices
# son los indices (0-based) de las filas de encabezado repetidas, que
# ExcelWriter usa para resaltarlas (ver HIGHLIGHT_FILL).
module ExportRelabeling
  class QuotaProgressBuilder
    HEADER = %w[Quota Variable Value Goal Achieved Pending].freeze
    NOT_FOUND = 'variable not found in any exported file'
    CROSS_SOURCE_UNSUPPORTED = 'crossed quota between main file and a loop -- review manually'

    # sources: array de { headers:, rows:, status_variable:, complete_value: }
    # (ver ExcelReader::Header/Sheet) -- uno por cada .xlsx del zip (principal,
    # fichas, etc.), en el orden que sea. El "principal" se identifica solo:
    # es el unico que tiene la variable de sistema "status".
    #
    # collapse_loop_quotas: true por defecto (comportamiento de arriba, para
    # las cuotas que salen de Confirmit). Las cuotas declaradas a mano por
    # un PM en el mail (ver ExportRelabeling::ManualQuotaRequestParser)
    # NUNCA deben colapsar aunque su variable viva en un loop -- el PM puso
    # una meta especifica por cada precode a proposito (ej. "tipoficha:
    # A=50 B=60"), no es un contador interno tipo Confirmit que haya que
    # tratar como una sola meta repetida.
    def self.call(quotas:, sources:, collapse_loop_quotas: true)
      new(quotas, sources, collapse_loop_quotas).call
    end

    def initialize(quotas, sources, collapse_loop_quotas = true)
      @quotas = quotas
      @sources = sources
      @collapse_loop_quotas = collapse_loop_quotas
    end

    # Orden natural por nombre (quota1, quota2, ..., quota10 -- no
    # alfabetico puro, que pondria "quota10" antes que "quota2"), y una
    # fila en blanco entre los bloques de cada cuota para que se lean como
    # tablas separadas, no una sola tabla larga sin cortes.
    def call
      blocks = @quotas.sort_by { |quota| natural_sort_key(quota[:name]) }
                      .map { |quota| build_quota_block(quota) }
                      .reject { |block| block[:rows].empty? }

      merge_blocks(blocks)
    end

    private

    def natural_sort_key(name)
      name.to_s.scan(/\d+|\D+/).map { |chunk| chunk.match?(/\A\d+\z/) ? chunk.to_i : chunk }
    end

    def blank_row
      Array.new(HEADER.length)
    end

    def merge_blocks(blocks)
      rows = []
      header_indices = []

      blocks.each_with_index do |block, index|
        rows << blank_row unless index.zero?
        header_indices << rows.length
        rows.concat(block[:rows])
      end

      { rows: rows, header_indices: header_indices }
    end

    def build_quota_block(quota)
      body_rows = build_quota_rows(quota)
      return { rows: [] } if body_rows.empty?

      { rows: [HEADER] + dedupe_leading_columns(body_rows) }
    end

    # "Quota" y "Variable" tienen el mismo valor para todas las filas de un
    # mismo grupo (misma cuota, mismo campo) -- a pedido de Diego se deja
    # solo en la primera linea del grupo, en blanco en las siguientes, para
    # que la tabla se lea como bloques en vez de repetir el mismo texto en
    # cada fila.
    def dedupe_leading_columns(rows)
      previous = nil

      rows.map do |row|
        quota_name, field = row[0], row[1]
        current = [quota_name, field]
        deduped = current == previous ? [nil, nil] : [quota_name, field]
        previous = current

        deduped + row[2..-1]
      end
    end

    def build_quota_rows(quota)
      return [] unless all_fields_present?(quota)

      total_cells, field_cells = quota[:cells].partition { |cell| cell[:fields].empty? }
      single_cells, crossed_cells = field_cells.partition { |cell| cell[:fields].length == 1 }

      total_cells.map { |cell| build_total_row(quota[:name], cell) } +
        build_single_field_rows(quota[:name], single_cells) +
        crossed_cells.map { |cell| build_crossed_row(quota[:name], cell) }
    end

    def all_fields_present?(quota)
      field_names = quota[:cells].flat_map { |cell| cell[:fields].map { |f| f[:name] } }
      field_names.all? { |name| source_for(name) }
    end

    # Una celda sin QuotaField es la meta total del proyecto (confirmado con
    # un caso real, ej. "2997 completas") -- se cuenta contra el archivo
    # principal (los entrevistados), no contra ningun loop.
    def build_total_row(quota_name, cell)
      source = main_source
      count = source && count_matching(source, [])

      row(quota_name, '(total)', '-', cell[:limit], count)
    end

    def build_single_field_rows(quota_name, cells)
      cells.group_by { |cell| cell[:fields].first[:name] }.flat_map do |field_name, group|
        source = source_for(field_name)
        should_collapse = @collapse_loop_quotas && source && loop_source?(source)
        next [build_collapsed_row(quota_name, field_name, group, source)] if should_collapse

        group.map { |cell| build_field_row(quota_name, cell, source) }
      end
    end

    def build_field_row(quota_name, cell, source)
      field = cell[:fields].first
      count = source && count_matching(source, [field])

      row(quota_name, field[:name], match_value(field), cell[:limit], count)
    end

    # "la meta siempre esta en la primera linea de las variaciones" -- se
    # toma el limite de la primera celda del grupo tal cual, sin promediar
    # ni exigir que las demas coincidan.
    def build_collapsed_row(quota_name, field_name, group, source)
      values = group.map { |cell| match_value(cell[:fields].first) }
      count = count_any(source, field_name, values)

      row(quota_name, field_name, values.join(', '), group.first[:limit], count)
    end

    def build_crossed_row(quota_name, cell)
      description = cell[:fields].map { |f| f[:name] }.join(' + ')
      values = cell[:fields].map { |f| match_value(f) }.join(' + ')

      sources = cell[:fields].map { |f| source_for(f[:name]) }
      return row(quota_name, description, values, cell[:limit], NOT_FOUND) if sources.any?(&:nil?)
      return row(quota_name, description, values, cell[:limit], CROSS_SOURCE_UNSUPPORTED) if sources.uniq.length > 1

      row(quota_name, description, values, cell[:limit], count_matching(sources.first, cell[:fields]))
    end

    def match_value(field)
      field[:label] || field[:value]
    end

    def row(quota_name, field, value, limit, count)
      pending = count.is_a?(Integer) ? limit - count : nil
      [quota_name, field, value, limit, count || NOT_FOUND, pending]
    end

    def source_for(field_name)
      @sources.find { |source| header_index(source, field_name) }
    end

    # El principal es el unico que tiene la variable de sistema "status"
    # (confirmado que un loop de fichas trae su propio campo de estado con
    # otro nombre, ej. "fichaestado", nunca "status").
    def main_source
      @sources.find { |source| header_index(source, source[:status_variable]) }
    end

    def loop_source?(source)
      source != main_source
    end

    # fields: array de {name:, value:} -- vacio para "solo status=complete,
    # sin ningun otro filtro" (la meta total del proyecto).
    def count_matching(source, fields)
      return nil unless source

      indices = fields.map { |f| header_index(source, f[:name]) }
      status_idx = header_index(source, source[:status_variable])

      source[:rows].count do |data_row|
        next false if status_idx && !complete?(data_row[status_idx], source)

        fields.each_with_index.all? { |f, i| data_row[indices[i]].to_s == match_value(f).to_s }
      end
    end

    def count_any(source, field_name, values)
      return nil unless source

      field_idx = header_index(source, field_name)
      status_idx = header_index(source, source[:status_variable])
      accepted = values.map(&:to_s)

      source[:rows].count do |data_row|
        next false if status_idx && !complete?(data_row[status_idx], source)

        accepted.include?(data_row[field_idx].to_s)
      end
    end

    def complete?(status_value, source)
      status_value.to_s.casecmp?(source[:complete_value].to_s)
    end

    def header_index(source, variable_name)
      return nil if variable_name.blank?

      source[:headers].find_index { |header| header.variable_name.to_s.casecmp?(variable_name) }
    end
  end
end
