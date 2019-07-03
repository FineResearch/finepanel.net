# frozen_string_literal: true

class Payment < ApplicationRecord
  def self.get_payment_history_for_user(respid)
    Payment.where(respid: respid).order(email_date: :desc)
  end
end
