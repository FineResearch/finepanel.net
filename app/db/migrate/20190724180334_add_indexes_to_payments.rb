# frozen_string_literal: true

class AddIndexesToPayments < ActiveRecord::Migration[5.2]
  def change
    add_index :payments, :respid
    add_index :payments,
              %i[respid project_name credit concept email_date],
              name: :index_payment_on_respid_project_credit_concept_email
  end
end
