# frozen_string_literal: true

# Parsea los campos de metadata que Confirmit agrega al cuerpo del mail de
# la Rule que dispara un export (visto en un envio real, 2026-09-30):
#
#   Attached to this email you will find the survey data export of "..."
#   Survey ID: p833174000229
#   Survey Name: "FP-18358N - 3418357_ATU CPNPC Early Stages Imfinzi"
#   Active Database: Production
#   ...
#   Interview Status Filter: All(unfiltered)
#   Export completed at 9/30/2026 5:55:53 PM
#   Comment: dcasar@fine-research.com
#
# Ninguno de estos campos esta garantizado -- un PM probando a mano (sin
# pasar por una Rule real) nunca los tiene, y el parser tiene que devolver
# nil silenciosamente en ese caso (nunca romper export_sync por esto, ver
# el comentario de #valid_export_sender? sobre no frenar el envio).
#
# "Survey Name" se usa como titulo legible del proyecto en el mail de
# entrega (ver ExportDeliveryMailer#subject_for) -- unica fuente confirmada
# hasta ahora, el SurveySchema de Confirmit no lo trae (confirmado contra
# un proyecto real).
#
# "Survey ID" (project_id) normalmente sale del nombre del archivo
# adjunto (ver MailerController#export_sync, /p\d+/) -- pero un PM puede
# personalizar ese nombre al armar la Rule en Confirmit, y ahi el regex
# contra el filename no encuentra nada. Diego: "en esos casos donde el
# pXXXX falte, es tomar el numero de la nota que viene en el mensaje".
# Se devuelve aca tambien, en minuscula (mismo formato que usa el resto
# de la app, ej. "p833174000229"), para que el controller lo use como
# fallback -- nunca como fuente primaria, el filename sigue siendo mas
# confiable cuando esta presente.
module ExportRelabeling
  class ConfirmitExportEmailParser
    SURVEY_NAME = /Survey Name:\s*"([^"]*)"/.freeze
    INTERVIEW_STATUS_FILTER = /Interview Status Filter:\s*([^\t\r\n]+?)(?=\t|\r?\n|\z)/.freeze
    SURVEY_ID = /Survey ID:\s*(p\d+)/i.freeze

    def self.call(body)
      new(body).call
    end

    def initialize(body)
      @body = body.to_s
    end

    def call
      {
        project_title: @body[SURVEY_NAME, 1].presence,
        interview_status_filter: @body[INTERVIEW_STATUS_FILTER, 1]&.strip&.presence,
        survey_id: @body[SURVEY_ID, 1]&.downcase&.presence
      }
    end
  end
end
