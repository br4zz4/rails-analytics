# frozen_string_literal: true

require "securerandom"
require "digest"

module RailsAnalytics
  class DailySalt < ActiveRecord::Base
    self.table_name = "rails_analytics_daily_salts"

    validates :date, presence: true, uniqueness: true
    validates :salt, presence: true

    def self.for_date(date = Date.today)
      find_or_create_by!(date: date) do |ds|
        ds.salt = SecureRandom.hex(32)
      end.salt
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      derive_salt(date)
    end

    def self.derive_salt(date)
      key = Rails.application.try(:secret_key_base) || Rails.application.try(:secrets).try(:secret_key_base) || "rails_analytics_fallback"
      Digest::SHA256.hexdigest("#{key}:#{date.iso8601}")
    end
  end
end