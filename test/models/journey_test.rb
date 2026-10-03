# frozen_string_literal: true

require "test_helper"

module RailsAnalytics
  class JourneyTest < ActiveSupport::TestCase
    setup do
      @visit = Visit.create!(
        anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "twitter.com",
        device_type: "mobile", viewport: "390x844", language: "pt-BR",
        utm_source: "twitter", utm_campaign: "jan25",
        landing_page_path: "/?utm_source=twitter",
        started_at: Time.zone.parse("2026-10-03 10:00:00")
      )
      @visit.events.create!(name: "doacao-click", time: @visit.started_at + 30.seconds,
                            properties: { value: "btn-hero" })
      @visit.events.create!(name: "scroll-depth", time: @visit.started_at + 60.seconds,
                            properties: { mark: 75 })
      @visit.events.create!(name: "outbound-click", time: @visit.started_at + 90.seconds,
                            properties: { target: "instagram.com" })
      @visit.events.create!(name: "form-submit", time: @visit.started_at + 120.seconds,
                            properties: { form: "newsletter" })
    end

    test "first step is the landing pageview" do
      steps = Journey.new(@visit).to_h[:steps]

      assert_equal :pageview, steps.first[:kind]
      assert_equal "/", steps.first[:label]
    end

    test "steps are ordered by time and mapped to kinds" do
      steps = Journey.new(@visit).to_h[:steps]

      assert_equal %i[pageview click scroll outbound form], steps.map { |s| s[:kind] }
    end

    test "click label uses value property when present" do
      steps = Journey.new(@visit).to_h[:steps]

      assert_equal "btn-hero", steps[1][:label]
      assert_includes steps[1][:detail], "value: btn-hero"
    end

    test "scroll step shows the mark" do
      steps = Journey.new(@visit).to_h[:steps]

      assert_equal "Scroll 75%", steps[2][:label]
    end

    test "origin falls back to direct" do
      @visit.update!(referrer_domain: nil)
      journey = Journey.new(@visit).to_h

      assert_equal "direct", journey[:origin]
    end

    test "utm and context are exposed" do
      journey = Journey.new(@visit).to_h

      assert_equal "twitter", journey[:utm][:source]
      assert_equal "jan25", journey[:utm][:campaign]
      assert_equal "mobile", journey[:device]
      assert journey[:duration] >= 120
    end

    test "never exposes PII columns" do
      journey = Journey.new(@visit).to_h

      assert_nil journey[:anonymity_key]
      assert_nil journey[:masked_ip]
      journey[:steps].each { |s| refute s[:label].to_s.include?("8.8.8.0") }
    end
  end
end
