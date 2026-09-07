# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::CollectTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    @verifier = Rails.application.message_verifier("rails_analytics_tracker")
    @token = @verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)
  end

  test "collect creates visit with masked IP and event" do
    assert_difference -> { RailsAnalytics::Visit.count }, 1 do
      post "/rails_analytics/collect",
           params: { path: "/home", referrer_domain: "twitter.com", device_type: "desktop", viewport: "1440x900", language: "pt-BR", nonce: "abc", events: [{ name: "click", time: Time.current.iso8601 }] }.to_json,
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    end

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_match(/\.0$/, visit.masked_ip) # masked
    assert_equal "twitter.com", visit.referrer_domain
    assert_equal 1, visit.events.count
  end

  test "collect accepts token in body (sendBeacon compatibility)" do
    assert_difference -> { RailsAnalytics::Visit.count }, 1 do
      post "/rails_analytics/collect",
           params: { path: "/home", token: @token, events: [] }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :no_content
  end

  test "collect without token returns 401" do
    post "/rails_analytics/collect",
         params: { path: "/home" }.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "collect with malformed json returns 204 gracefully" do
    assert_no_difference -> { RailsAnalytics::Visit.count } do
      post "/rails_analytics/collect",
           params: "not-json",
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    end

    assert_response :no_content
  end

  test "collect with massive path truncates" do
    post "/rails_analytics/collect",
         params: { path: "x" * 3000, referrer_domain: "t.co", device_type: "mobile", viewport: "390x844", language: "en", nonce: "abc", events: [] }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }

    assert_response :no_content
    assert RailsAnalytics::Visit.last.landing_page_path.length <= 2000
  end
end

class RailsAnalytics::TrackerTest < ActionDispatch::IntegrationTest
  test "tracker.js is served" do
    get "/rails_analytics/tracker.js"
    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert_includes response.body, "RailsAnalytics"
    assert_includes response.body, "sendBeacon"
  end

  test "token returns valid signed token" do
    get "/rails_analytics/token"
    assert_response :success
    body = JSON.parse(response.body)
    verifier = Rails.application.message_verifier("rails_analytics_tracker")
    assert_nothing_raised { verifier.verified(body["token"], purpose: :tracker) }
  end

  test "dashboard.css is served" do
    get "/rails_analytics/dashboard.css"
    assert_response :success
    assert_equal "text/css", response.media_type
  end
end

class RailsAnalytics::DashboardTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all

    v = RailsAnalytics::Visit.create!(anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "google.com",
                                       device_type: "desktop", viewport: "1440x900", language: "pt-BR",
                                       utm_source: "twitter", utm_campaign: "launch",
                                       started_at: Time.current)
    v.events.create!(name: "doacao-click", time: Time.current)

    RailsAnalytics.config.auth_callback = -> { true }
    I18n.locale = :"pt-BR"
  end

  teardown do
    RailsAnalytics.config.auth_callback = :authenticate_admin!
    I18n.locale = I18n.default_locale
  end

  test "dashboard overview renders core elements" do
    get "/rails_analytics/"
    assert_response :success
    assert_includes response.body, "Rails Analytics"
    assert_includes response.body, "svg"
    assert_includes response.body, "google.com"
    assert_includes response.body, "doacao-click"
    assert_includes response.body, "twitter"
    assert_includes response.body, "launch"
  end

  test "dashboard HTML never contains PII" do
    get "/rails_analytics/"
    refute_includes response.body, "8.8.8.0"  # masked IP not exposed
    refute_includes response.body, "k1"        # anonymity key not exposed
  end

  test "events page is accessible" do
    get "/rails_analytics/events"
    assert_response :success
  end

  test "visits page is accessible" do
    get "/rails_analytics/visits"
    assert_response :success
  end

  test "footer shows LGPD compliance" do
    get "/rails_analytics/"
    assert_includes response.body, "retenção"
  end

  test "dashboard without auth redirects" do
    RailsAnalytics.config.auth_callback = -> { false }
    get "/rails_analytics/"
    assert_response :redirect
  end
end

class RailsAnalytics::SecurityTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics.config.auth_callback = -> { true }
  end

  teardown do
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end

  test "rate limit kicks in after 20 requests per masked IP" do
    verifier = Rails.application.message_verifier("rails_analytics_tracker")
    token = verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)

    20.times do
      post "/rails_analytics/collect",
           params: { path: "/x", token: token, events: [] }.to_json,
           headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "203.0.113.5" }
    end
    assert_response :no_content

    post "/rails_analytics/collect",
         params: { path: "/x", token: token, events: [] }.to_json,
         headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "203.0.113.5" }
    assert_response :too_many_requests
  end

  test "different masked IPs are throttled independently" do
    verifier = Rails.application.message_verifier("rails_analytics_tracker")
    token = verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)

    25.times do |i|
      post "/rails_analytics/collect",
           params: { path: "/x", token: token, events: [] }.to_json,
           headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "198.51.#{i}.7" }
    end
    assert_response :no_content, "25 requests de IPs diferentes não devem ser throttled juntos"
  end
end