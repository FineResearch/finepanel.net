# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    def create
      resource = User.find_from_email_and_password(params[:user][:email], params[:user][:password])
      if resource.present?
        resource.remember_me = params[:remember_me]
        sign_in(resource_name, resource)
        respond_with resource, location: after_sign_in_path_for(resource)
      else
        flash[:error] = t('messages.error.login')
        redirect_to root_path
      end
    end

    def redirect_user_login
      resource = User.find_from_respid_spanel_and_encrypted_email(params[:r], params[:s], params[:e])
      if resource.present?
        sign_in(resource_name, resource)
        cookies[:respid] = params[:r]
        cookies[:user_email] = resource.email
        user_data = resource.profile_data_from_email(resource.email)
        cookies[:country_id] = user_data[:country_id]
        cookies[:locale] = ConfigurationReader.language(user_data[:country_id])
      else
        flash[:error] = t('messages.error.login')
      end
      redirect_to root_path
    end

    def destroy
      super
      reset_session
      flash[:success] = t('messages.notice.logout')
    end
  end
end
