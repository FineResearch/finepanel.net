# frozen_string_literal: true

require 'aws-sdk-s3'
require 'aws-sdk-lambda'

# Compila un .sps ya re-etiquetado (ver RelabelSpssExportWorker) a .sav
# invocando una funcion Lambda aparte (ver lambda/pspp_compiler/), en vez
# de correr PSPP en este mismo contenedor -- la base de la app (Alpine 3.7,
# ver Dockerfile.release) no puede instalar NI correr PSPP de ninguna
# forma (confirmado: revienta con segfault tanto instalandolo via apk como
# corriendo un binario ya compilado copiado desde un Alpine mas nuevo,
# independiente de la arquitectura). PSPP corre limpio en Debian, asi que
# el compile se movio a su propio contenedor, en su propio lado.
#
# El .sps que llega aca ya tiene el FILE HANDLE apuntando a
# LAMBDA_DATA_PATH y el SAVE OUTFILE apuntando a LAMBDA_SAV_PATH --
# convenciones fijas que coinciden con lo que usa el handler de la Lambda
# de su lado (ver lambda/pspp_compiler/handler.py), asi que no hace falta
# mandarle esos paths en el payload, solo las keys de S3 de donde bajar/
# subir cada archivo.
module ExportRelabeling
  class PsppLambdaClient
    LAMBDA_DATA_PATH = '/tmp/data.asc'
    LAMBDA_SAV_PATH = '/tmp/output.sav'

    BUCKET = ENV.fetch('PSPP_COMPILE_BUCKET', 'finepanel-pspp-compile-784064929014')
    FUNCTION_NAME = ENV.fetch('PSPP_LAMBDA_FUNCTION', 'finepanel-pspp-compiler')
    REGION = ENV.fetch('AWS_REGION', 'us-east-1')

    def self.compile(sps_path:, data_path:, output_path:)
      new(sps_path, data_path, output_path).compile
    end

    def initialize(sps_path, data_path, output_path)
      @sps_path = sps_path
      @data_path = data_path
      @output_path = output_path
      @job_id = SecureRandom.uuid
    end

    def compile
      upload(@sps_path, sps_key)
      upload(@data_path, data_key)

      invoke_lambda
      download(sav_key, @output_path)
    ensure
      cleanup
    end

    private

    # Invocacion sincrona (RequestResponse) -- el worker de Sidekiq ya
    # corre en background, no hay problema en esperar acá los ~segundos
    # que tarda compilar. http_read_timeout mas generoso que el default del
    # SDK, para no cortar la espera antes de que Lambda termine con un
    # archivo de datos grande.
    def invoke_lambda
      response = lambda_client.invoke(
        function_name: FUNCTION_NAME,
        invocation_type: 'RequestResponse',
        payload: { bucket: BUCKET, sps_key: sps_key, data_key: data_key, sav_key: sav_key }.to_json
      )

      raise "PSPP Lambda fallo: #{response.payload.read}" if response.function_error
    end

    def sps_key
      "#{@job_id}/input.sps"
    end

    def data_key
      "#{@job_id}/data.asc"
    end

    def sav_key
      "#{@job_id}/output.sav"
    end

    def upload(local_path, key)
      s3_client.put_object(bucket: BUCKET, key: key, body: File.read(local_path, mode: 'rb'))
    end

    def download(key, local_path)
      response = s3_client.get_object(bucket: BUCKET, key: key)
      File.write(local_path, response.body.read, mode: 'wb')
    end

    # Los archivos de un compile son de un solo uso -- se borran apenas
    # termina (haya salido bien o mal), no hace falta una lifecycle rule en
    # el bucket para esto.
    def cleanup
      [sps_key, data_key, sav_key].each do |key|
        s3_client.delete_object(bucket: BUCKET, key: key)
      rescue StandardError
        nil
      end
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(region: REGION)
    end

    def lambda_client
      @lambda_client ||= Aws::Lambda::Client.new(region: REGION, http_read_timeout: 150)
    end
  end
end
