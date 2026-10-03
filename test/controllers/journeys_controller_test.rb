# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::JourneysControllerTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    RailsAnalytics.config.auth_callback = -> { true }

    visit = RailsAnalytics::Visit.create!(
      anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "google.com",
      device_type: "desktop", viewport: "1440x900", language: "pt-BR",
      utm_source: "twitter", utm_campaign: "jan25",
      landing_page_path: "/",
      started_at: Time.current
    )
    visit.events.create!(name: "doacao-click", time: Time.current, properties: { value: "btn-hero" })
    visit.events.create!(name: "scroll-depth", time: Time.current + 5, properties: { mark: 50 })
  end

  teardown do
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end

  test "journeys returns 200 with session cards" do
    get "/rails_analytics/journeys"
    assert_response :success

    assert_includes response.body, "ra-journey"
    assert_includes response.body, "ra-journey-step"
    assert_includes response.body, "google.com"
  end

  test "journeys filters by event name" do
    get "/rails_analytics/journeys", params: { event: "scroll-depth" }
    assert_response :success
    assert_includes response.body, "ra-journey"

    get "/rails_analytics/journeys", params: { event: "doacao-click" }
    assert_response :success
    assert_includes response.body, "btn-hero"
  end

  test "journeys HTML never contains PII" do
    get "/rails_analytics/journeys"
    refute_includes response.body, "8.8.8.0"
    refute_includes response.body, "k1"
  end

  test "journeys is protected by auth" do
    RailsAnalytics.config.auth_callback = -> { false }
    get "/rails_analytics/journeys"
    assert_response :redirect
  end
end
