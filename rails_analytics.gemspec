# frozen_string_literal: true

require_relative "lib/rails_analytics/version"

Gem::Specification.new do |s|
  s.name        = "rails_analytics"
  s.version     = RailsAnalytics::VERSION
  s.summary     = "Analytics estilo Umami para Rails — coleta de tráfego e dashboard."
  s.description = "Engine Rails que coleta tráfego via pixel e tracker JS (sem cookies), salva no banco da host app e exibe um dashboard moderno e simples."
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