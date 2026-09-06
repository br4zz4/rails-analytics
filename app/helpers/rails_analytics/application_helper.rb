# frozen_string_literal: true

module RailsAnalytics
  module ApplicationHelper
    def rails_analytics_tracker_tag(options = {})
      endpoint = options[:endpoint] || "/rails_analytics"
      tag.script(src: "#{endpoint}/tracker.js",
                 data: { rails_analytics: true, endpoint: endpoint },
                 async: true)
    end
  end
end