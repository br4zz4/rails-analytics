# frozen_string_literal: true

module RailsAnalytics
  module RackAttack
    def self.configure
      return unless defined?(::Rack::Attack)

      masked_ip = ->(req) {
        ip = req.env["HTTP_CF_CONNECTING_IP"] || req.ip
        RailsAnalytics::IpMask.mask(ip) || "unknown"
      }

      # Throttle the collection endpoint: 20 req/min per masked IP.
      # Path ends in /collect regardless of mount_path.
      ::Rack::Attack.throttle("rails_analytics_collect_by_ip", limit: 20, period: 60.seconds) do |req|
        if req.post? && req.path.end_with?("/collect")
          masked_ip.call(req)
        end
      end
    end
  end
end