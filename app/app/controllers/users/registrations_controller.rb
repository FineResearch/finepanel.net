# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    def create
      user_params = ConfirmitGateway.new_account(params)
      resource = User.new(user_params)
      if resource.save
        resource.email = params[:email]
        sign_in(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        flash.now[:error] = t('messages.error.errors')
        render :new
      end
    end
  end
end
