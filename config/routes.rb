Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "pets/:username", to: "pets#show"
      post "pets/:username/hatch", to: "pets#hatch"
      patch "pets/:username/equipment", to: "pets#equipment"
      get "community_pet", to: "community_pets#show"
      patch "community_pet/customization", to: "community_pets#update"
    end
  end
end
