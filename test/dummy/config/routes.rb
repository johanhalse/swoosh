Rails.application.routes.draw do
  resources :payments, only: %i[create destroy]
  post "swish/callbacks", to: "swish/callbacks#create", as: :swish_callbacks
end
