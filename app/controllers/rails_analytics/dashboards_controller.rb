# frozen_string_literal: true

module RailsAnalytics
  class DashboardsController < ApplicationController
    def overview
      since = default_since
      daily_series = Stats.visits_by_day(since: since)

      @stats = {
        total_visits: Stats.total_visits(since: since),
        total_unique: Stats.total_unique_visitors(since: since),
        total_events: Stats.total_events(since: since),
        bounce_rate: Stats.bounce_rate(since: since),
        top_sources: Stats.top_sources(limit: 10, since: since),
        top_events: Stats.top_events(limit: 10, since: since),
        devices: Stats.devices(since: since),
        utm_breakdown: Stats.utm_breakdown(since: since)
      }
      @chart = ChartBuilder.new(
        daily_series.map { |date, count| { date: date, count: count } }
      ).build
    end

    def events
      @event_name = params[:name]
      @page = (params[:page] || 1).to_i
      @events = Stats.events_paginated(name: @event_name.presence, page: @page, since: default_since)
    end

    def visits
      @page = (params[:page] || 1).to_i
      @visits = Stats.visits_paginated(page: @page, since: default_since)
    end

    private

    def default_since
      RailsAnalytics.config.since_default.ago
    end
  end
end