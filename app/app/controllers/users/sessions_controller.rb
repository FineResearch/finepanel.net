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
        redirect_existent_user_login(resource, exit_param: 'exit')
      else
        flash[:error] = t('messages.error.login')
        redirect_to root_path
      end
    end

    def destroy
      super
      cookies.delete(:currency)
      cookies.delete(:country_id)
      reset_session
      flash[:success] = t('messages.notice.logout')
    end

    private 

    def redirect_existent_user_login(resource, exit_param:)
      if params[exit_param].present?
        # redirect to user's portal with surveys info
        surveys_params = ConfirmitGateway.get_surveys_for_redirect_to_portal(resource, params[:r])
        redirect_to resource.user_profile_url(params[:r]) + "&#{exit_param}=#{params[exit_param]}" + surveys_params
      else
        sign_in(resource_name, resource)
        set_cookies_for_redirect_user_login(resource)  
        create_post_from_redirect_user_login(resource) if params[:post].present?
        redirect_to root_path
      end
    end

    def set_cookies_for_redirect_user_login(resource)
      cookies[:respid] = params[:r]
      cookies[:user_email] = resource.email
      user_data = resource.profile_data_from_email(resource.email)
      cookies[:currency] = ConfirmitGateway.get_currency_for_user(user_data)
      cookies[:country_id] = user_data[:country_id]
      cookies[:locale] = ConfigurationReader.language(user_data[:country_id])
    end

    def create_post_from_redirect_user_login(resource)
      user_info = resource.info_for_post(cookies[:respid])
      resource.posts.create(text: params[:post], kind: 'text', user_info: user_info)
    end
  end
end
