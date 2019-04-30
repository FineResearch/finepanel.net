Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions", registrations: "users/registrations" }
  authenticated :user do
    root to: 'dashboard#index'
  end
  root to: 'home#index'

  get 'faq', to: 'home#faq'
  get 'countries/cities/:country_id', to: 'countries#cities'
end
