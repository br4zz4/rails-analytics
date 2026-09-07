# frozen_string_literal: true

module RailsAnalytics
  module ApplicationHelper
    # Single source of truth: the engine's mount point is whatever the host
    # declared in routes.rb (`mount RailsAnalytics::Engine => "/..."`). We derive
    # the tracker endpoint from the engine's own route helper, so there is no
    # separate `mount_path` to keep in sync. `options[:endpoint]` still allows an
    # explicit override (e.g. when serving the tracker from a CDN).
    def rails_analytics_tracker_tag(options = {})
      tracker = options[:tracker] || rails_analytics.tracker_path
      endpoint = options[:endpoint] || rails_analytics.root_path.chomp("/")
      tag.script(src: tracker,
                 data: { rails_analytics: true, endpoint: endpoint },
                 defer: true)
    end
  end
end