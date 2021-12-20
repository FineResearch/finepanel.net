LastParticipationPresenter = Struct.new(:participation, :participations, :locale) do
  def last_participations
    last_payment_text = extract_last_payment
    _participations = LastParticipationsBlueprint.render_as_json(participations)
    { lastParticipation: participation, participations: _participations, lastPayment: last_payment_text }
  end

  def extract_last_payment
    payments = []
    ordered_participations = sort_participations(participations)

    ordered_participations.each do |participation|
      payments << participation if participation[:status] == "8"
    end

    formatted_payment_text(payments.first)
  end

  def formatted_payment_text(payment)
    return 'false' unless payment.present?
    date = I18n.with_locale(locale) { I18n.l(payment[:payment_date].to_time, format: :participation_date) }
    value = (payment[:fee].to_i).abs

    "#{value} #{I18n.with_locale(locale){I18n.t('dashboard.survey_history.the')}} #{date}"
  end

  def sort_participations(participations)
    participations.sort_by { |participation| participation[:payment_date].to_time }.reverse!
  end
end
