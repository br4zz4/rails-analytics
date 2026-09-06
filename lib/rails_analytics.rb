# frozen_string_literal: true

require_relative "rails_analytics/version"
require_relative "rails_analytics/configuration"
require_relative "rails_analytics/ip_mask"
require_relative "rails_analytics/identity"
require_relative "rails_analytics/stats"
require_relative "rails_analytics/engine" if defined?(Rails::Railtie)

module RailsAnalytics
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config if block_given?
    end
  end
end