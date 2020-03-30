# frozen_string_literal: true

class HomeController < ApplicationController
  def index; end

  def faq; end

  def commitment; end

  def aacd
    campaign_profile_path = ConfigurationReader.aacd_profile_path
    @data = get_campaign_payment_data(campaign_profile_path)
  end

  def stc
    stc_mx_profile_path = ConfigurationReader.stc_mx_profile_path
    stc_co_profile_path = ConfigurationReader.stc_co_profile_path
    @data_mx = get_campaign_payment_data(stc_mx_profile_path)
    @data_co = get_campaign_payment_data(stc_co_profile_path)
  end

  def icw
    campaign_profile_path = ConfigurationReader.icw_profile_path
    @data = get_campaign_payment_data(campaign_profile_path)
  end

  private

  def get_campaign_payment_data(campaign_profile_path)
    campaign_user_data = ConfirmitGateway.get_user_attrs_from_profile(campaign_profile_path)
    {
      total_earned: ConfirmitGateway.get_payments_for_user(campaign_user_data)[:total],
      currency: ConfirmitGateway.get_currency_for_user(campaign_user_data)
    }
  end
end
