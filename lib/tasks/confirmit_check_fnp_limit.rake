# frozen_string_literal: true

# Chequeo de solo lectura: identifica el ultimo nodo de script dentro de
# "asignacion de p en base a Project" (mapeo codigo de proyecto Fine <-> Forsta,
# usado cuando la programacion NO es de Fine en Confirmit) y cuenta sus lineas,
# para saber si esta cerca del limite (~523 lineas) y conviene crear un nodo
# nuevo a mano. No crea ni modifica nada en Confirmit.
#
# Uso: bin/rails confirmit:check_fnp_limit
# (el proyecto es siempre el mismo, p1773348171, no hace falta pasarlo)
namespace :confirmit do
  task check_fnp_limit: :environment do
    begin
      result = FinePanelSetup::ConfirmitSoapClient.new.check_fnp_assignment_limit
    rescue StandardError => e
      puts "Error: #{e.class} - #{e.message}"
      next
    end

    puts "Proyecto: #{FinePanelSetup::ConfirmitSoapClient::FNP_ASSIGNMENT_PROJECT_ID}"
    puts "Ultimo nodo: #{result[:node_name]}"
    puts "Lineas: #{result[:line_count]} / #{result[:line_limit]} (quedan #{result[:lines_remaining]})"
    puts(result[:near_limit] ? '⚠️  Cerca del limite -- conviene crear un nodo nuevo pronto.' : 'OK, todavia hay margen.')
  end
end
