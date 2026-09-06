# frozen_string_literal: true

module RailsAnalytics
  class PageView < ActiveRecord::Base
    self.table_name = "rails_analytics_page_views"

    validates :path, presence: true

    scope :since, ->(time) { where(arel_table[:viewed_at].gteq(time)) }

    def self.ip_hash_from(ip)
      Digest::SHA256.hexdigest("#{ip}#{Rails.application.secret_key_base}")
    end
  end
end