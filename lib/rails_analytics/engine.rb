# frozen_string_literal: true

module RailsAnalytics
  class Engine < ::Rails::Engine
    isolate_namespace RailsAnalytics

    config.generators do |g|
      g.test_framework :minitest
      g.helper false
      g.assets false
    end

    initializer "rails_analytics.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.precompile += %w[rails_analytics/tracker.js rails_analytics/dashboard.css]
      end
    end

    initializer "rails_analytics.helper" do
      ActiveSupport.on_load(:action_view) do
        include RailsAnalytics::ApplicationHelper
      end
    end

    initializer "rails_analytics.rack_attack" do
      if defined?(Rack::Attack)
        require "rails_analytics/rack_attack"
        RailsAnalytics::RackAttack.configure
      end
    end
  end
end