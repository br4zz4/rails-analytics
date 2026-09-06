# frozen_string_literal: true

module RailsAnalytics
  class DashboardsController < ApplicationController
    def index
      @stats = DashboardStats.call(PageView)
      @chart = ChartBuilder.new(@stats[:daily_series]).build
    end
  end
end