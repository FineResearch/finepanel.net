# frozen_string_literal: true

# Trae el schema de un proyecto y arma un ConfirmitVariableLookup listo
# para usar -- usado por los 2 workers de relabeling (SPSS y Excel, cada
# uno independiente, ver la conversacion sobre por que son 2 procesos
# separados). Si la API no responde o el proyecto no tiene schema
# accesible, no hay que frenar el re-etiquetado por eso -- se devuelve nil
# y el llamador sigue sin lookup (cae 100% al parseo del texto del export).
module ExportRelabeling
  class ConfirmitSchemaFetcher
    # Distinguido aparte de cualquier otro fallo (timeout, proyecto sin
    # schema, etc.) para poder alertar especificamente "hay que autorizar
    # la API" -- ver ExportRelabeling::ProcessingAlertNotifier. El
    # faultstring real de Confirmit es literalmente "Server was unable to
    # process request. ---> Permission denied." (confirmado contra un
    # proyecto real, p833174000229).
    class PermissionDeniedError < StandardError; end

    PERMISSION_DENIED_PATTERN = /Permission denied/i.freeze

    def self.call(project_id)
      client = ::FinePanelSetup::ConfirmitSoapClient.new
      key = client.log_on
      schema = client.send(:get_raw_survey_schema, project_id: project_id, key: key)
      ConfirmitVariableLookup.new(schema[:inner])
    rescue StandardError => e
      Rails.logger.error("[ConfirmitSchemaFetcher] no se pudo traer el schema de #{project_id}: #{e.class} #{e.message}")
      raise PermissionDeniedError, e.message if e.message.to_s.match?(PERMISSION_DENIED_PATTERN)

      nil
    end
  end
end
