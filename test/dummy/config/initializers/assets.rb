# Be sure to restart your server when running with the asset pipeline.
# Guard: the engine test bundle may not load sprockets-rails.
if defined?(Sprockets::Railtie)
  Rails.application.config.assets.version = "1.0"
end
