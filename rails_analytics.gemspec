# frozen_string_literal: true

require_relative "lib/rails_analytics/version"

Gem::Specification.new do |s|
  s.name        = "rails_analytics"
  s.version     = RailsAnalytics::VERSION
  s.summary     = "Privacy-first analytics engine for Rails — cookie-less, LGPD-compliant."
  s.description = "Rails Engine with server-side tracker, aggregated dashboard, IP masking, daily anonymity key rotation, UTM tracking, and 6-month retention. No third-party analytics dependencies."
  s.authors     = ["br4zz4"]
  s.email       = ["dev@br4zz4.com"]
  s.homepage    = "https://github.com/br4zz4/rails-analytics"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.0"

  s.files = Dir["lib/**/*", "app/**/*", "config/**/*", "db/**/*"] + %w[README.md MIT-LICENSE]
  s.require_paths = ["lib"]

  s.add_dependency "rails", ">= 7.0"

  s.metadata["rubygems_mfa_required"] = "true"
end