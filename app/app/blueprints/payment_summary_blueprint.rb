class PaymentSummaryBlueprint < Blueprinter::Base
  fields :payments, :history, :currency, :date, :record
end
