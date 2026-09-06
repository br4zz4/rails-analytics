# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::IdentityTest < ActiveSupport::TestCase
  def test_same_inputs_same_key
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0 (X11; Linux x86_64) Chrome/120.0", date: Date.new(2026, 1, 1))
    k2 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0 (X11; Linux x86_64) Chrome/120.0", date: Date.new(2026, 1, 1))
    assert_equal k1, k2
  end

  def test_different_ip_different_key
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.today)
    k2 = RailsAnalytics::Identity.key(masked_ip: "1.2.3.0", user_agent: "Mozilla/5.0", date: Date.today)
    refute_equal k1, k2
  end

  def test_different_date_different_key
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.new(2026, 1, 1))
    k2 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.new(2026, 1, 2))
    refute_equal k1, k2
  end

  def test_similar_ua_same_bucket
    ua1 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0"
    ua2 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/121.0.0.0"
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: ua1, date: Date.today)
    k2 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: ua2, date: Date.today)
    assert_equal k1, k2 # Same OS + browser family → same bucket
  end

  def test_cannot_recover_ip_from_key
    key = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.today)
    refute_includes key, "8.8.8.0"
    refute_includes key.downcase, "8.8.8.0"
  end

  def test_coarse_ua_bucket_detects_chrome_on_mac
    ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    bucket = RailsAnalytics::Identity.coarse_ua_bucket(ua)
    assert_equal "Chrome:macOS", bucket
  end

  def test_coarse_ua_bucket_detects_safari_on_ios
    ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    bucket = RailsAnalytics::Identity.coarse_ua_bucket(ua)
    assert_equal "Safari:iOS", bucket
  end

  def test_coarse_ua_bucket_fallback_unknown
    bucket = RailsAnalytics::Identity.coarse_ua_bucket("curl/7.79.1")
    assert_equal "Other:Other", bucket
  end

  def test_coarse_ua_bucket_handles_nil
    bucket = RailsAnalytics::Identity.coarse_ua_bucket(nil)
    assert_equal "Other:Other", bucket
  end
end