# frozen_string_literal: true

require 'aws-sdk-s3'

# Guarda una copia del zip ORIGINAL que llega de Confirmit, para poder reproducir un
# reclamo dias despues. Hoy el zip se borra apenas termina el proceso, y para entender
# el desfasaje de FP-18810G faltaban justamente los archivos originales (.sps/.dat), que
# habia que volver a pedir.
#
# - Va al mismo bucket que usa PsppLambdaClient, bajo "evidence/AAAA/MM/DD/" y cifrado
#   (los exports traen datos de los encuestados).
# - Se conserva unos 30 dias: lo borra una regla de ciclo de vida del bucket sobre ese prefijo
#   (ver RETENTION_DAYS y la documentacion del deploy); este codigo no borra nada.
# - Es de MEJOR ESFUERZO: si falla (permisos, S3) se loguea y el export sigue como siempre.
module ExportRelabeling
  class EvidenceStore
    PREFIX = 'evidence'
    RETENTION_DAYS = 30

    def self.save(zip_path:, project_id:, export_type:)
      new(zip_path, project_id, export_type).save
    end

    def self.location(key)
      "s3://#{PsppLambdaClient::BUCKET}/#{key}"
    end

    def initialize(zip_path, project_id, export_type)
      @zip_path = zip_path
      @project_id = project_id
      @export_type = export_type
    end

    # Devuelve la key guardada, o nil si no se pudo.
    def save
      return nil unless @zip_path && File.exist?(@zip_path)

      key = build_key
      s3_client.put_object(
        bucket: PsppLambdaClient::BUCKET, key: key, body: File.open(@zip_path, 'rb'), server_side_encryption: 'AES256'
      )
      key
    rescue StandardError => e
      Rails.logger.error("[EvidenceStore] no se pudo guardar el zip original de #{@project_id.presence || 'proyecto no identificado'}: #{e.class} #{e.message}")
      nil
    end

    private

    def build_key
      now = Time.now.utc
      name = File.basename(@zip_path).gsub(/[^\w.\-]+/, '_')
      "#{PREFIX}/#{now.strftime('%Y/%m/%d')}/#{@project_id.presence || 'sin_proyecto'}/#{@export_type}_#{SecureRandom.hex(4)}_#{name}"
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(region: PsppLambdaClient::REGION)
    end
  end
end
