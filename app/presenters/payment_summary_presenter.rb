PaymentSummaryPresenter = Struct.new(:payments, :currency, :history) do
  def payment_summary
    py = payments.present? ? payments[:total] : '0'
    ht = history.present? ? history.credit.to_s : ''
    cr = currency.try(:delete, '$')
    date = history.present? ? history.email_date.strftime("%d-%m-%Y") : ''
    record = history.present?

    { payments: py, history: ht, currency: cr, date: date, record: record }
  end
end
