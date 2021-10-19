AacdPresenter = Struct.new(:aacd_amount) do
  def aacd_object
    aacd_value = ActionController::Base.helpers.number_to_currency(aacd_amount[:total_earned], unit: aacd_amount[:currency])

    {aacd_br: aacd_value}
  end
end
