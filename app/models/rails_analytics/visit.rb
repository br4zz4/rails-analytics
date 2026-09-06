# frozen_string_literal: true

module RailsAnalytics
  class Visit < ActiveRecord::Base
    self.table_name = "rails_analytics_visits"

    has_many :events, class_name: "RailsAnalytics::Event", dependent: :delete_all

    validates :anonymity_key, presence: true
    validates :masked_ip, presence: true
    validates :started_at, presence: true

    scope :since, ->(time) { where(arel_table[:started_at].gteq(time)) }
    scope :for_key, ->(key) { where(anonymity_key: key) }

    INACTIVITY_WINDOW = 4.hours

    def self.find_or_create_for(anonymity_key, attrs = {})
      recent = for_key(anonymity_key)
               .where(started_at: (attrs[:started_at] || Time.current) - INACTIVITY_WINDOW..)
               .order(started_at: :desc)
               .first

      return recent if recent

      create!(attrs.merge(anonymity_key: anonymity_key))
    end

    def self.parse_utm_params(path)
      return {} if path.blank?

      query = URI.parse(path).query.to_s
      params = URI.decode_www_form(query).to_h
      {
        utm_source:   params["utm_source"],
        utm_medium:   params["utm_medium"],
        utm_campaign: params["utm_campaign"],
        utm_term:     params["utm_term"],
        utm_content:  params["utm_content"]
      }
    rescue URI::InvalidURIError
      {}
    end
  end
end