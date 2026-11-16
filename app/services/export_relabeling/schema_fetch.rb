# frozen_string_literal: true

# Resultado de traer el schema de Confirmit para un export: el lookup, o el motivo
# por el que no se pudo (ver ProcessingAlertNotifier.hold). Compartido por los dos
# workers (SPSS y Excel) para que decidan igual si el export se retiene.
#
#   failure: nil | :permission_denied | :schema_unavailable | :project_unidentified
#   detail:  el error tecnico, para el aviso
module ExportRelabeling
  class SchemaFetch
    Result = Struct.new(:lookup, :failure, :detail)

    def self.call(project_id)
      return Result.new(nil, :project_unidentified, nil) if project_id.blank?

      Result.new(ConfirmitSchemaFetcher.call(project_id), nil, nil)
    rescue ConfirmitSchemaFetcher::PermissionDeniedError => e
      Result.new(nil, :permission_denied, e.message)
    rescue ConfirmitSchemaFetcher::SchemaUnavailableError => e
      Result.new(nil, :schema_unavailable, e.message)
    end
  end
end
