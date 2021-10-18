StcPresenter = Struct.new(:mx_amount, :col_amount) do
  def stc_object
    mx_value = ActionController::Base.helpers.number_to_currency(mx_amount[:total_earned], unit: mx_amount[:currency])
    col_value = ActionController::Base.helpers.number_to_currency(col_amount[:total_earned], unit: col_amount[:currency])

    {stc_mx: mx_value, stc_col: col_value}
  end
end
