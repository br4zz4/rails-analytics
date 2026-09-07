# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::DailySaltTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::DailySalt.delete_all
  end

  test "for_date creates salt on first call" do
    salt1 = RailsAnalytics::DailySalt.for_date(Time.current.to_date)
    assert_kind_of String, salt1
    assert_equal 64, salt1.length # SHA256 hex digest = 64 chars
  end

  test "for_date returns same salt for same date" do
    salt1 = RailsAnalytics::DailySalt.for_date(Time.current.to_date)
    salt2 = RailsAnalytics::DailySalt.for_date(Time.current.to_date)
    assert_equal salt1, salt2
  end

  test "for_date returns different salt for different dates" do
    salt1 = RailsAnalytics::DailySalt.for_date(Time.current.to_date)
    salt2 = RailsAnalytics::DailySalt.for_date(Time.current.to_date - 1)
    refute_equal salt1, salt2
  end

  test "for_date persists only one row per date" do
    3.times { RailsAnalytics::DailySalt.for_date(Time.current.to_date) }
    assert_equal 1, RailsAnalytics::DailySalt.where(date: Time.current.to_date).count
  end

  test "for_date without db falls back to deterministic derivation" do
    salt = RailsAnalytics::DailySalt.derive_salt(Time.current.to_date)
    assert_kind_of String, salt
    assert_equal 64, salt.length
    # Same date → same salt
    assert_equal salt, RailsAnalytics::DailySalt.derive_salt(Time.current.to_date)
    # Different date → different salt
    refute_equal salt, RailsAnalytics::DailySalt.derive_salt(Time.current.to_date - 1)
  end
end