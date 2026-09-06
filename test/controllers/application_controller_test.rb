# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "redirects when host auth rejects" do
    RailsAnalytics.config.auth_callback = -> { false }
    get "/rails_analytics/"
    assert_response :redirect
  ensure
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end

  test "allows when host auth accepts" do
    RailsAnalytics.config.auth_callback = -> { true }
    get "/rails_analytics/"
    assert_response :success
  ensure
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end
end