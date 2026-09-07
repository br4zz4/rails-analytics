# frozen_string_literal: true

RailsAnalytics::Engine.routes.draw do
  get "tracker.js" => "analytics#tracker"
  get "dashboard.css" => "analytics#dashboard_css", as: "dashboard_css"
  post "collect" => "analytics#collect"
  get  "token" => "analytics#token"
  root to: "dashboards#overview"
  get "events" => "dashboards#events"
  get "visits" => "dashboards#visits"
end