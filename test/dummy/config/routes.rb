Rails.application.routes.draw do
  resources :payments, only: :create
end
