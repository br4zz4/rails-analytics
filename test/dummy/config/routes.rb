Rails.application.routes.draw do
  mount RailsAnalytics::Engine => "/rails_analytics"

  get "up" => "rails/health#show", as: :rails_health_check

  get "login" => "application#login"
  get "logout" => "application#logout"

  root to: "application#index"
end