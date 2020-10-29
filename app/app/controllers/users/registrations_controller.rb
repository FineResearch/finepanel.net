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

    def edit
      @user_data = current_user.profile_data(cookies[:respid])
    end

    def update
      if ConfirmitGateway.update_user(cookies[:respid], current_user.spanel, params)
        flash[:notice] = t('messages.notice.user_updated')
        redirect_to root_path
      else
        flash.now[:error] = t('messages.error.errors')
        render :edit
      end
    end

    def edit_payment_data
      @user_data = current_user.profile_data(cookies[:respid])
    end

    def update_payment_data
      if ConfirmitGateway.update_user_payment_data(cookies[:respid], current_user.spanel, params)
        flash[:notice] = t('messages.notice.user_updated')
        redirect_to root_path
      else
        flash.now[:error] = t('messages.error.errors')
        render :edit
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

    def password_recovery
    end

    def send_password
      if params[:email].present? && User.find_from_email(params[:email]).present?
        RegistrationMailer.password_recovery_email(params[:email], User.automated_password(params[:email])).deliver_later
        flash[:notice] = t('registrations.password_recovery.password_sent')
        redirect_to root_path
      else
        flash.now[:alert] = t('registrations.password_recovery.email_not_found')
        render :password_recovery
      end
    end
  end
end
