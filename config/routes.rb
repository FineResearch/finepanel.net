Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions", registrations: "users/registrations" }
  root to: 'home#index'
  get 'faq', to: 'home#faq'
  get 'countries/cities/:country_id', to: 'countries#cities'
end
