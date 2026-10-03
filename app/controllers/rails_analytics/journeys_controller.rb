# frozen_string_literal: true

module RailsAnalytics
  class JourneysController < ApplicationController
    def index
      @event_name = params[:event]
      @page = (params[:page] || 1).to_i
      @journeys = Stats.journeys(event: @event_name.presence, page: @page)
      @event_names = Stats.event_counts_by_name.keys.sort
    end
  end
end
