if RailsAnalytics.respond_to?(:configure)
  RailsAnalytics.configure do |config|
    config.mount_path = "/rails_analytics"
  end
end
