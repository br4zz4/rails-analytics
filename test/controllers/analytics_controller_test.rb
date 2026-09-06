# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    @verifier = Rails.application.message_verifier("rails_analytics_tracker")
    @valid_token = @verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)
  end

  def valid_payload(overrides = {})
    {
      path: "/blog/hello",
      referrer_domain: "google.com",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      nonce: SecureRandom.hex(8),
      events: [{ name: "click", time: Time.current.iso8601 }]
    }.merge(overrides)
  end

  test "POST collect with valid token creates visit and event" do
    assert_difference -> { RailsAnalytics::Visit.count }, 1 do
      assert_difference -> { RailsAnalytics::Event.count }, 1 do
        post "/rails_analytics/collect",
             params: valid_payload.to_json,
             headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}", "REMOTE_ADDR" => "8.8.8.8" }
      end
    end

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_equal "8.8.8.0", visit.masked_ip
    assert_equal "desktop", visit.device_type
  end

  test "POST collect without token returns 401" do
    post "/rails_analytics/collect",
         params: valid_payload.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "POST collect with malformed payload returns 204 gracefully" do
    assert_no_difference -> { RailsAnalytics::Visit.count } do
      post "/rails_analytics/collect",
           params: "not json",
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}" }
    end

    assert_response :no_content
  end

  test "POST collect masks IP before storing" do
    post "/rails_analytics/collect",
         params: valid_payload.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}", "REMOTE_ADDR" => "192.168.1.55" }

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_equal "192.168.1.0", visit.masked_ip
  end

  test "POST collect parses UTM params from path" do
    post "/rails_analytics/collect",
         params: valid_payload(path: "/?utm_source=twitter&utm_campaign=jan25").to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}" }

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_equal "twitter", visit.utm_source
    assert_equal "jan25", visit.utm_campaign
  end

  test "GET token returns signed token" do
    get "/rails_analytics/token"

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("token")
    assert_nothing_raised do
      @verifier.verified(body["token"], purpose: :tracker)
    end
  end

  test "GET token returns fresh token each request" do
    get "/rails_analytics/token"
    t1 = JSON.parse(response.body)["token"]

    get "/rails_analytics/token"
    t2 = JSON.parse(response.body)["token"]

    refute_equal t1, t2
  end

  test "GET tracker.js serves javascript" do
    get "/rails_analytics/tracker.js"

    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert_includes response.body, "RailsAnalytics"
  end

  test "GET dashboard.css serves css" do
    get "/rails_analytics/dashboard.css"

    assert_response :success
    assert_equal "text/css", response.media_type
    assert_includes response.body, "ra"
  end

  test "tracker.js HTML does not leak secrets" do
    get "/rails_analytics/tracker.js"
    refute_includes response.body, "secret"
    refute_includes response.body, "key_base"
  end
end