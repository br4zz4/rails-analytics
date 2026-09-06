# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::StatsTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    seed_data
  end

  def seed_data
    now = Time.current

    # Visit 1: com events (bounce = false)
    v1 = RailsAnalytics::Visit.create!(anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "google.com",
                                        landing_page_path: "/?utm_source=twitter&utm_campaign=jan25",
                                        device_type: "desktop", viewport: "1440x900", language: "pt-BR",
                                        utm_source: "twitter", utm_campaign: "jan25",
                                        started_at: now)
    v1.events.create!(name: "doacao-click", time: now, properties: { value: 50 })
    v1.events.create!(name: "email-click", time: now)

    # Visit 2: sem events (bounce = true)
    v2 = RailsAnalytics::Visit.create!(anonymity_key: "k2", masked_ip: "1.2.3.0", referrer_domain: "instagram.com",
                                        landing_page_path: "/blog",
                                        device_type: "mobile", viewport: "390x844", language: "en",
                                        started_at: now)

    # Visit 3: sem events (bounce = true)
    v3 = RailsAnalytics::Visit.create!(anonymity_key: "k3", masked_ip: "5.6.7.0", referrer_domain: "direct",
                                        landing_page_path: "/contato",
                                        device_type: "tablet", viewport: "768x1024", language: "pt-BR",
                                        started_at: 1.day.ago)

    # Visit 4: sem events (bounce = true)
    v4 = RailsAnalytics::Visit.create!(anonymity_key: "k4", masked_ip: "9.9.9.0", referrer_domain: "google.com",
                                        landing_page_path: "/",
                                        device_type: "desktop", viewport: "1920x1080", language: "pt-BR",
                                        started_at: 1.day.ago)
  end

  test "total_visits returns count" do
    assert_equal 4, RailsAnalytics::Stats.total_visits
  end

  test "total_visits with since filter" do
    assert_equal 2, RailsAnalytics::Stats.total_visits(since: 12.hours.ago)
  end

  test "total_unique_visitors returns distinct anonymity keys" do
    assert_equal 4, RailsAnalytics::Stats.total_unique_visitors
  end

  test "total_events returns event count" do
    assert_equal 2, RailsAnalytics::Stats.total_events
  end

  test "visits_by_day returns hash" do
    result = RailsAnalytics::Stats.visits_by_day
    assert_kind_of Hash, result
  end

  test "unique_visitors_by_day returns hash" do
    result = RailsAnalytics::Stats.unique_visitors_by_day
    assert_kind_of Hash, result
  end

  test "bounce_rate is 0.75" do
    # 3 visits sem events, 1 com events → 3/4 = 0.75
    assert_equal 0.75, RailsAnalytics::Stats.bounce_rate
  end

  test "top_sources returns sorted hash" do
    result = RailsAnalytics::Stats.top_sources
    assert_kind_of Hash, result
    assert_equal "google.com", result.keys.first
    assert_equal 2, result.values.first
  end

  test "top_events returns sorted hash" do
    result = RailsAnalytics::Stats.top_events
    assert_equal({ "doacao-click" => 1, "email-click" => 1 }, result)
  end

  test "event_counts_by_name returns hash" do
    result = RailsAnalytics::Stats.event_counts_by_name
    assert_equal({ "doacao-click" => 1, "email-click" => 1 }, result)
  end

  test "events_by_name filters by event name over time" do
    result = RailsAnalytics::Stats.events_by_name("doacao-click")
    assert_kind_of Hash, result
    assert_equal 1, result.values.sum
  end

  test "devices returns breakdown" do
    result = RailsAnalytics::Stats.devices
    assert_equal({ "desktop" => 2, "mobile" => 1, "tablet" => 1 }, result)
  end

  test "utm_breakdown returns aggregation" do
    result = RailsAnalytics::Stats.utm_breakdown
    assert_equal 1, result.count { |r| r["utm_source"] == "twitter" }
    assert_equal 1, result.count { |r| r["utm_campaign"] == "jan25" }
  end

  test "visits_paginated returns array with total count" do
    page = RailsAnalytics::Stats.visits_paginated(page: 1, per_page: 2)
    assert_equal 2, page[:data].length
    assert_equal 4, page[:total]
  end

  test "events_paginated returns array with total count" do
    page = RailsAnalytics::Stats.events_paginated(name: "doacao-click", page: 1, per_page: 10)
    assert_equal 1, page[:data].length
    assert_equal 1, page[:total]
  end
end