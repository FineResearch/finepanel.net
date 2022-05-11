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
    get 'survey_list', to: 'dashboard#survey_list'
    get 'payment_info', to: 'dashboard#payment_info'
    get 'participations', to: 'dashboard#participations'
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
    get 'garrahan'
    get 'stc'
    get 'dynamed_disabled'
  end

  get 'countries/cities/:country_id', to: 'countries#cities'

  namespace :api do
    namespace :v1 do
      devise_for :users,
        defaults: { format: :json },
        skip: [:invitations, :passwords, :confirmations, :unlocks],
        path: '',
        path_names: { sign_in: 'login', sign_out: 'logout' }
        as :user do
          get :send_password, to: 'registrations#send_password'
        end

      resources :payments, only: [:index] do
        get :payment_history, on: :collection
      end

      resources :surveys, only: [:index] do
        get :participations, on: :collection
      end

      resources :news_feed, only: [:index, :create, :destroy] do
        post :increment_view_count, on: :member
        get :search, on: :collection
      end

      resources :user_information, only: [:index] do
        put :update_profile, on: :collection
        put :update_payment_data, on: :collection
      end

      resources :posts, only: [:index, :create] do
        get :delete, on: :member
      end

      resources :comments, only: [:create] do
        get :delete, on: :member
      end

      resources :news_comment, only: [:create] do
        get :delete, on: :member
      end

      resources :home, only: [] do
        get :stc, on: :collection
        get :aacd, on: :collection
        get :garrahan, on: :collection
      end

      resources :refer_colleague, only: [:create]

      post :news_mailer, to: 'news_mailer#create'
    end
  end

end
