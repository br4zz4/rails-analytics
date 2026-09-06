# frozen_string_literal: true

require "ipaddr"

module RailsAnalytics
  module IpMask
    def self.mask(ip)
      return nil if ip.blank?

      addr = IPAddr.new(ip.to_s)
      if addr.ipv4?
        addr.mask(24).to_s
      elsif addr.ipv6?
        if addr.ipv4_mapped?
          IPAddr.new("::ffff:#{addr.native.mask(24)}").to_s
        else
          addr.mask(48).to_s
        end
      end
    rescue IPAddr::InvalidAddressError
      nil
    end
  end
end