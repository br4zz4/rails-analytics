# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    RailsAnalytics.config.auth_callback = -> { true }

    v = RailsAnalytics::Visit.create!(anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "google.com",
                                       device_type: "desktop", viewport: "1440x900", language: "pt-BR",
                                       utm_source: "twitter", utm_campaign: "jan25",
                                       started_at: Time.current)
    v.events.create!(name: "click", time: Time.current)
  end

  teardown do
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end

  test "overview returns 200" do
    get "/rails_analytics/"
    assert_response :success
    assert_includes response.body, "svg"
  end

  test "overview HTML never contains anonymity_key" do
    get "/rails_analytics/"
    refute_includes response.body, RailsAnalytics::Visit.last.anonymity_key
  end

  test "overview HTML never contains masked_ip" do
    get "/rails_analytics/"
    refute_includes response.body, "8.8.8.0"
  end

  test "events returns 200" do
    get "/rails_analytics/events"
    assert_response :success
  end

  test "events filters by name" do
    get "/rails_analytics/events", params: { name: "click" }
    assert_response :success
  end

  test "visits returns 200" do
    get "/rails_analytics/visits"
    assert_response :success
  end
end