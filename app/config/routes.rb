require 'sidekiq/web'

Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions", registrations: "users/registrations" }
  authenticated :user do
    root to: 'dashboard#index'
    mount Sidekiq::Web => '/sidekiq'

    devise_scope :user do
      namespace :users do
        get 'refer_colleague', to: 'registrations#refer_colleague'
        post 'create_colleague', to: 'registrations#create_colleague'
        get 'edit_payment_data', to: 'registrations#edit_payment_data'
        post 'update_payment_data', to: 'registrations#update_payment_data'
      end
    end
    get 'list_all_projects', to: 'surveys#list_all_projects'
    get 'payment_history', to: 'dashboard#payment_history'
  end

  root to: 'home#index'

  post 'mailer', to: 'mailer#sync'

  devise_scope :user do
    namespace :users do
      get 'redirect_user_login', to: 'sessions#redirect_user_login'
      get 'password_recovery', to: 'registrations#password_recovery'
      post 'send_password', to: 'registrations#send_password'
    end
  end

  resources :posts, only: [:create, :show] do
    member do
      get "download"
      get "delete"
    end
  end
  resources :comments, only: [:create] do
    member do
      get "delete"
    end
  end

  controller :home do
    get 'faq'
    get 'contact'
    get 'commitment'
    get 'privacy_policy'
    get 'aacd'
    get 'icw'
    get 'stc'
  end

  get 'countries/cities/:country_id', to: 'countries#cities'
end
