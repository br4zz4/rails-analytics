# frozen_string_literal: true

module RailsAnalytics
  module ApplicationHelper
    def rails_analytics_tracker_tag(options = {})
      endpoint = options[:endpoint] || RailsAnalytics.config.mount_path
      tag.script(src: "#{endpoint}/tracker.js",
                 data: { rails_analytics: true, endpoint: endpoint },
                 defer: true)
    end
  end
end