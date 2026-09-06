# frozen_string_literal: true

require "digest"

module RailsAnalytics
  module Identity
    # Coarse UA bucket: "<browser_family>:<os_family>"
    # Never stores the full user agent string.
    def self.coarse_ua_bucket(user_agent)
      return "Other:Other" if user_agent.nil? || user_agent.empty?

      ua = user_agent.to_s

      os = if ua.match?(/Windows|Win64|Win32/i)
             "Windows"
           elsif ua.match?(/iPhone|iPad|iOS/i)
             "iOS"
           elsif ua.match?(/Macintosh|Mac OS X|macOS/i)
             "macOS"
           elsif ua.match?(/Android/i)
             "Android"
           elsif ua.match?(/Linux|X11/i)
             "Linux"
           else
             "Other"
           end

      browser = if ua.match?(/Edg\//i)
                  "Edge"
                elsif ua.match?(/OPR|Opera/i)
                  "Opera"
                elsif ua.match?(/Chrome/i)
                  "Chrome"
                elsif ua.match?(/Safari/i)
                  "Safari"
                elsif ua.match?(/Firefox/i)
                  "Firefox"
                else
                  "Other"
                end

      "#{browser}:#{os}"
    end

    def self.key(masked_ip:, user_agent:, date:)
      bucket = coarse_ua_bucket(user_agent)
      salt = RailsAnalytics::DailySalt.for_date(date)
      Digest::SHA256.hexdigest("#{masked_ip}:#{bucket}:#{salt}")
    end
  end
end