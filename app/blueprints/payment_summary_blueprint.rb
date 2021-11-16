class PaymentSummaryBlueprint < Blueprinter::Base
  fields :payments, :history, :currency, :record

  field :date do |payment, options|
    "#{I18n.with_locale(options[:locale]){I18n.t('dashboard.survey_history.the')}} #{I18n.with_locale(options[:locale]) { I18n.l(payment[:date].try(:to_datetime), format: :participation_date) }}"
  end
end
