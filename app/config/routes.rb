Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions", registrations: "users/registrations" }
  authenticated :user do
    root to: 'dashboard#index'
  end
  root to: 'home#index'

  post 'mailer', to: 'mailer#sync'

  devise_scope :user do
    get 'users/redirect_user_login', to: 'users/sessions#redirect_user_login'
  end
  
  get 'faq', to: 'home#faq'
  get 'countries/cities/:country_id', to: 'countries#cities'
end
