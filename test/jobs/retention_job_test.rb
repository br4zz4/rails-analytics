# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::RetentionJobTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all

    @old_visit = RailsAnalytics::Visit.create!(anonymity_key: "old1", masked_ip: "1.1.1.0", started_at: 7.months.ago)
    @old_visit.events.create!(name: "click", time: 7.months.ago)

    @recent_visit = RailsAnalytics::Visit.create!(anonymity_key: "new1", masked_ip: "2.2.2.0", started_at: 1.day.ago)
    @recent_visit.events.create!(name: "scroll", time: 1.day.ago)
  end

  test "deletes visits older than 6 months" do
    assert_difference -> { RailsAnalytics::Visit.count }, -1 do
      RailsAnalytics::RetentionJob.perform_now
    end
    assert RailsAnalytics::Visit.exists?(@recent_visit.id), "recente deve ser preservado"
    refute RailsAnalytics::Visit.exists?(@old_visit.id), "antigo deve ser deletado"
  end

  test "deletes events for deleted visits" do
    assert_difference -> { RailsAnalytics::Event.count }, -1 do
      RailsAnalytics::RetentionJob.perform_now
    end
  end

  test "is idempotent" do
    3.times { RailsAnalytics::RetentionJob.perform_now }
    assert RailsAnalytics::Visit.exists?(@recent_visit.id)
    refute RailsAnalytics::Visit.exists?(@old_visit.id)
    assert_equal 1, RailsAnalytics::Visit.count
  end

  test "does not delete recent visits" do
    RailsAnalytics::RetentionJob.perform_now
    assert_equal 1, RailsAnalytics::Visit.count
  end
end