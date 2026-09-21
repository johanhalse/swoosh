Rails.application.routes.draw do
  resources :payments, only: :create
  post "swish/callbacks", to: "swish/callbacks#create", as: :swish_callbacks
end
