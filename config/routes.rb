Rails.application.routes.draw do
  root to: 'home#index'
  get 'faq', to: 'home#faq'
end
