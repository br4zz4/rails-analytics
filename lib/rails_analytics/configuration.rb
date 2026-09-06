# frozen_string_literal: true

module RailsAnalytics
  class Configuration
    attr_accessor :auth_callback, :mount_path, :since_default

    def initialize
      @auth_callback = :authenticate_admin!
      @mount_path = "/analytics"
      @since_default = 30.days
    end

    def auth_callback_callable?
      auth_callback.respond_to?(:call)
    end
  end
end