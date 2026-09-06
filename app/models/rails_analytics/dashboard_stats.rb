# frozen_string_literal: true

module RailsAnalytics
  # Agregações do dashboard em SQL puro (rápidas, sem cache em memória no piloto).
  class DashboardStats
    DAYS = 30

    def self.call(model)
      new(model).call
    end

    def initialize(model)
      @model = model
      @now = Time.current
    end

    def call
      table = @model.arel_table
      {
        views_today: @model.where(table[:viewed_at].gteq(@now.beginning_of_day)).count,
        views_7d: @model.since(7.days.ago).count,
        views_30d: @model.since(DAYS.days.ago).count,
        unique_visitors_30d: @model.since(DAYS.days.ago).distinct.count(:session_id),
        pages_per_visit: pages_per_visit,
        daily_series: daily_series,
        top_pages: top(:path, 10),
        top_referrers: top(:referrer, 10),
        devices: devices_breakdown
      }
    end

    private

    def pages_per_visit
      scope = @model.since(DAYS.days.ago)
      total = scope.count
      sessions = scope.distinct.count(:session_id)
      return 0.0 if sessions.zero?

      (total.to_f / sessions).round(2)
    end

    def daily_series
      rows = @model.since(DAYS.days.ago)
                   .group("date(viewed_at)")
                   .order("date(viewed_at)")
                   .count

      series = []
      (DAYS.days.ago.to_date..@now.to_date).each do |day|
        series << { date: day, count: rows[day.to_s] || rows[day] || 0 }
      end
      series
    end

    def top(column, limit)
      @model.since(DAYS.days.ago).where.not(column => nil)
             .group(column).order("count_all desc").limit(limit).count
    end

    def devices_breakdown
      desktop = @model.since(DAYS.days.ago).where(screen_width: 768..).count
      mobile = @model.since(DAYS.days.ago).where(screen_width: ...768).count
      { desktop: desktop, mobile: mobile }
    end
  end
end