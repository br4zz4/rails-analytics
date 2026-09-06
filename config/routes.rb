# frozen_string_literal: true

RailsAnalytics::Engine.routes.draw do
  get "px.gif" => "analytics#px"
  get "tracker.js" => "analytics#tracker"
  get "dashboard.css" => "analytics#dashboard_css"
  post "collect" => "analytics#collect"
  get  "token" => "analytics#token"
  root to: "dashboards#index"
end