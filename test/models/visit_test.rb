# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::VisitTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all if defined?(RailsAnalytics::Event)
  end

  test "creates a visit with valid attributes" do
    visit = RailsAnalytics::Visit.create!(
      anonymity_key: "abc123",
      masked_ip: "8.8.8.0",
      referrer_domain: "google.com",
      landing_page_path: "/?utm_source=twitter",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: Time.current
    )
    assert visit.persisted?
    assert_equal "desktop", visit.device_type
  end

  test "since scope filters by started_at" do
    old = RailsAnalytics::Visit.create!(anonymity_key: "a", masked_ip: "1.1.1.0", started_at: 40.days.ago)
    recent = RailsAnalytics::Visit.create!(anonymity_key: "b", masked_ip: "2.2.2.0", started_at: 1.day.ago)

    result = RailsAnalytics::Visit.since(30.days.ago)
    assert_includes result, recent
    refute_includes result, old
  end

  test "for_key scope filters by anonymity_key" do
    v1 = RailsAnalytics::Visit.create!(anonymity_key: "key_a", masked_ip: "1.1.1.0", started_at: Time.current)
    v2 = RailsAnalytics::Visit.create!(anonymity_key: "key_b", masked_ip: "2.2.2.0", started_at: Time.current)

    result = RailsAnalytics::Visit.for_key("key_a")
    assert_equal [v1.id], result.pluck(:id)
  end

  test "find_or_create_for reuses visit within 4h window" do
    key = "test_key_reuse"
    t0 = Time.current

    v1 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "example.com",
      landing_page_path: "/page1",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: t0
    })

    v2 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "example.com",
      landing_page_path: "/page2",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: t0 + 3.hours
    })

    assert_equal v1.id, v2.id, "deve reutilizar a mesma visit dentro da janela de 4h"
  end

  test "find_or_create_for creates new visit after 4h window" do
    key = "test_key_new_window"

    v1 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "example.com",
      landing_page_path: "/page1",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: 5.hours.ago
    })

    v2 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "other.com",
      landing_page_path: "/page2",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: Time.current
    })

    refute_equal v1.id, v2.id, "deve criar nova visit após janela de 4h"
  end

  test "parse_utm_params extracts utm params" do
    utm = RailsAnalytics::Visit.parse_utm_params("/?utm_source=twitter&utm_campaign=jan25&utm_medium=social")
    assert_equal "twitter", utm[:utm_source]
    assert_equal "jan25", utm[:utm_campaign]
    assert_equal "social", utm[:utm_medium]
  end

  test "parse_utm_params returns empty hash for blank path" do
    assert_equal({}, RailsAnalytics::Visit.parse_utm_params(nil))
    assert_equal({}, RailsAnalytics::Visit.parse_utm_params(""))
  end
end