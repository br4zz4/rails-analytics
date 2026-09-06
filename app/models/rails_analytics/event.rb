# frozen_string_literal: true

module RailsAnalytics
  class Event < ActiveRecord::Base
    self.table_name = "rails_analytics_events"

    belongs_to :visit, class_name: "RailsAnalytics::Visit"

    validates :name, presence: true
    validates :time, presence: true

    scope :since, ->(time) { where(arel_table[:time].gteq(time)) }
    scope :named, ->(name) { where(name: name) }
  end
end