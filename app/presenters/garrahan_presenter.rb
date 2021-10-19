GarrahanPresenter = Struct.new(:garrahan_amount) do
  def garrahan_object
    garrahan_value = ActionController::Base.helpers.number_to_currency(garrahan_amount[:total_earned], unit: garrahan_amount[:currency])

    {garrahan: garrahan_value}
  end
end
