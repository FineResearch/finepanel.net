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

    def refer_colleague
      @user = User.new
    end

    def create_colleague
      params[:fuente] = current_user.email
      user_params = ConfirmitGateway.new_colleague(params)
      colleague = User.new(user_params)
      if colleague.save
        redirect_to root_path
      else
        flash[:error] = t('messages.error.errors')
        redirect_to action: 'refer_colleague'
      end
    end
  end
end
