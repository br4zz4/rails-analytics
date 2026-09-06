# frozen_string_literal: true

module RailsAnalytics
  # Inherits from the host ApplicationController (RailsAdmin pattern) so the
  # auth callback (e.g. Devise authenticate_admin!) stays reachable via send.
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    layout "rails_analytics"

    before_action :authorize_admin!

    private

    def authorize_admin!
      callback = RailsAnalytics.config.auth_callback

      if callback.respond_to?(:call)
        redirect_to main_app.root_path unless instance_exec(&callback)
      else
        # Symbol: delegated to the host (Devise decides redirect/raise).
        send(callback)
      end
    end
  end
end