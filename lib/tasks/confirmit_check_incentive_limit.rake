# frozen_string_literal: true

# Chequeo de solo lectura: identifica el ultimo nodo de script dentro de
# "Asignacion de Incentivos por Proyecto" en un panel de Confirmit y cuenta sus
# lineas, para saber si esta cerca del limite (~400 lineas) y conviene crear un
# nodo nuevo a mano. No crea ni modifica nada en Confirmit.
#
# Uso: bin/rails confirmit:check_incentive_limit[p785267057]
# (si no se pasa project_id, usa el panel p785267057 por defecto)
namespace :confirmit do
  task :check_incentive_limit, [:project_id] => :environment do |_task, args|
    project_id = args[:project_id].presence || 'p785267057'

    begin
      result = FinePanelSetup::ConfirmitSoapClient.new.check_incentive_assignment_limit(project_id: project_id)
    rescue StandardError => e
      puts "Error: #{e.class} - #{e.message}"
      next
    end

    puts "Proyecto: #{project_id}"
    puts "Ultimo nodo: #{result[:node_name]}"
    puts "Lineas: #{result[:line_count]} / #{result[:line_limit]} (quedan #{result[:lines_remaining]})"
    puts(result[:near_limit] ? '⚠️  Cerca del limite -- conviene crear un nodo nuevo pronto.' : 'OK, todavia hay margen.')
  end
end
