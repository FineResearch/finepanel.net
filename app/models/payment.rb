# frozen_string_literal: true

class Payment < ApplicationRecord

  # -- Scopes --
  scope :with_credit, -> { where.not(credit: 0) }
  scope :paid, -> { where(concept: ['pago', 'Pago']) }

  def self.get_payment_history_for_user(respid)
    Payment.where(respid: respid).with_credit.order(email_date: :desc)
  end
end
