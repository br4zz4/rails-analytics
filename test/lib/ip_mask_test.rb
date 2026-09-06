# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::IpMaskTest < ActiveSupport::TestCase
  def test_ipv4_zeros_last_octet
    assert_equal "192.168.1.0", RailsAnalytics::IpMask.mask("192.168.1.55")
    assert_equal "8.8.8.0",     RailsAnalytics::IpMask.mask("8.8.8.8")
    assert_equal "10.0.0.0",    RailsAnalytics::IpMask.mask("10.0.0.1")
  end

  def test_ipv6_zeros_last_80_bits
    assert_equal "2001:db8::", RailsAnalytics::IpMask.mask("2001:db8::ff00:42:8329")
    assert_equal "::",         RailsAnalytics::IpMask.mask("::1")
  end

  def test_ipv6_mapped_ipv4
    assert_equal "::ffff:192.168.1.0", RailsAnalytics::IpMask.mask("::ffff:192.168.1.55")
  end

  def test_localhost_ipv4_masked
    assert_equal "127.0.0.0", RailsAnalytics::IpMask.mask("127.0.0.1")
  end

  def test_nil_returns_nil
    assert_nil RailsAnalytics::IpMask.mask(nil)
  end

  def test_blank_returns_nil
    assert_nil RailsAnalytics::IpMask.mask("")
  end

  def test_invalid_ip_returns_nil
    assert_nil RailsAnalytics::IpMask.mask("not-an-ip")
  end
end