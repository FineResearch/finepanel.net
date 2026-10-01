# frozen_string_literal: true

# Red de seguridad para los archivos temporales del pipeline de exports --
# tanto RelabelSpssExportWorker/RelabelExcelExportWorker como
# MailerController#export_sync ya borran lo suyo al terminar (ver sus
# propios "ensure"), pero eso no cubre un container que muere a mitad de
# proceso (ej. un redeploy mientras corre un job -- paso de verdad en esta
# misma sesion) ni el unico leak conocido de export_sync (un adjunto que no
# es un zip valido, ya arreglado por separado, pero esto igual cubre
# cualquier caso futuro parecido). Corre una vez por dia (ver
# config/sidekiq.yml), nunca en el momento del fallo -- no hace falta mas
# que eso para esta carga baja.
class ExportFilesCleanupWorker
  include Sidekiq::Worker
  sidekiq_options retry: 1

  MAX_AGE = 24.hours

  # tmp/feed_files/export esta en el volumen EFS compartido entre Api y
  # Sidekiq (ver taskdef-*.json) -- limpiarla desde cualquier container de
  # Sidekiq alcanza. tmp/relabel_spss y tmp/relabel_excel son locales al
  # disco de CADA container -- este job solo puede limpiar las del
  # container donde le toque correr, que es exactamente lo que hace falta
  # (cada container limpia lo suyo).
  SWEEP_DIRS = [
    Rails.root.join('tmp', 'feed_files', 'export'),
    Rails.root.join('tmp', 'relabel_spss'),
    Rails.root.join('tmp', 'relabel_excel')
  ].freeze

  def perform
    SWEEP_DIRS.each { |dir| sweep(dir) }
  end

  private

  def sweep(dir)
    return unless File.directory?(dir)

    Dir.children(dir).each { |name| sweep_entry(dir.join(name)) }
  end

  def sweep_entry(path)
    return if File.mtime(path) > MAX_AGE.ago

    FileUtils.rm_rf(path)
  rescue StandardError => e
    Rails.logger.error("[ExportFilesCleanupWorker] no se pudo borrar #{path}: #{e.class} #{e.message}")
  end
end
