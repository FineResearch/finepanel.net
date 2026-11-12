# frozen_string_literal: true

# Configuracion de envio del export de un proyecto de Confirmit (pXXXX), cargada
# en el Wizard: el mismo texto que un PM escribia en el Comment de la Rule --
# direcciones de destinatarios, "Quotas:" y "Report:" (ver
# ExportRelabeling::ManualQuotaRequestParser) -- pero sin el limite de 255
# caracteres de ese campo.
#
# Cuando un export llega con el cuerpo vacio (sin direcciones ni secciones), el
# sistema busca esto por el ID del proyecto (MailerController#export_sync). Si el
# mail trae algo, se usa tal cual y esto no interviene (asi una prueba con la
# direccion propia nunca le llega al cliente).
class ProjectExportSetting < ApplicationRecord
  PROJECT_ID_FORMAT = /\Ap\d{6,}\z/.freeze
  MAX_BODY_LENGTH = 20_000

  before_validation :normalize_project_id

  validates :project_id, presence: true, uniqueness: true
  validates :project_id, format: { with: PROJECT_ID_FORMAT, message: 'tiene que ser un ID de Confirmit, ej. p588393362171' },
                         allow_blank: true
  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

  def self.for_project(project_id)
    return nil if project_id.blank?

    find_by(project_id: project_id.to_s.strip.downcase)
  end

  def recipients
    ExportRelabeling::ExportRecipients.extract(body)
  end

  # Lo que el sistema entiende de este texto -- el Wizard lo muestra al guardar
  # para que el PM vea si interpreto bien las direcciones, cuotas y cruces.
  def preview
    manual = ExportRelabeling::ManualQuotaRequestParser.call(body)
    { recipients: recipients, quotas: manual[:quotas], reports: manual[:crosses] }
  end

  private

  def normalize_project_id
    self.project_id = project_id.to_s.strip.downcase.presence
  end
end
