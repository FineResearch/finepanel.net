class PaymentHistoryBlueprint < Blueprinter::Base
  identifier :id

  fields :credit

  field :date do |payment|
   payment.email_date.strftime("%d-%m-%Y")
  end

  field :name do |payment|
   payment.project_name
  end

  field :concept do |payment, options|
    translate_concept = I18n.with_locale(options[:locale]) { I18n.t('dashboard.payment_history.history_comment.filter') }
    payment.concept.downcase == 'filtro' ? translate_concept : payment.concept.try(:camelcase)
  end
end
