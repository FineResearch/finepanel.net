class LastParticipationsBlueprint < Blueprinter::Base
  fields :project, :status, :fee

  field :date do |participation|
    DateTime.parse(participation[:date]).strftime("%d-%m-%Y")
  end

  field :paymentDate do |participation|
    participation[:payment_date]
  end
end
