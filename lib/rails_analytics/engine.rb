# frozen_string_literal: true

module RailsAnalytics
  class Engine < ::Rails::Engine
    isolate_namespace RailsAnalytics

    config.generators do |g|
      g.test_framework :minitest
      g.helper false
      g.assets false
    end

    initializer "rails_analytics.assets.precompile" do |app|
      app.config.assets.precompile += %w[rails_analytics/tracker.js rails_analytics/dashboard.css]
    end

    initializer "rails_analytics.helper" do |app|
      ActiveSupport.on_load(:action_view) do
        include RailsAnalytics::ApplicationHelper
      end
    end

    config.to_prepare do
      ActionView::Base.include(RailsAnalytics::ApplicationHelper)
    end
  end
end