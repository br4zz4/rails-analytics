# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::EventTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    @visit = RailsAnalytics::Visit.create!(anonymity_key: "k", masked_ip: "1.1.1.0", started_at: Time.current)
  end

  test "creates event with name and properties" do
    event = @visit.events.create!(name: "doacao-click", time: Time.current, properties: { value: 50 })
    assert event.persisted?
    assert_equal "doacao-click", event.name
    assert_equal({ "value" => 50 }, event.properties)
  end

  test "properties defaults to empty hash" do
    event = @visit.events.create!(name: "click", time: Time.current)
    assert_equal({}, event.properties)
  end

  test "since scope filters by time" do
    old = @visit.events.create!(name: "e1", time: 40.days.ago)
    recent = @visit.events.create!(name: "e2", time: 1.day.ago)

    result = RailsAnalytics::Event.since(30.days.ago)
    assert_includes result, recent
    refute_includes result, old
  end

  test "named scope filters by name" do
    @visit.events.create!(name: "click", time: Time.current)
    @visit.events.create!(name: "scroll", time: Time.current)

    result = RailsAnalytics::Event.named("click")
    assert_equal 1, result.count
    assert_equal "click", result.first.name
  end

  test "belongs to visit" do
    event = @visit.events.create!(name: "click", time: Time.current)
    assert_equal @visit, event.visit
  end

  test "destroying visit deletes events" do
    @visit.events.create!(name: "e1", time: Time.current)
    @visit.events.create!(name: "e2", time: Time.current)

    assert_difference -> { RailsAnalytics::Event.count }, -2 do
      @visit.destroy
    end
  end
end