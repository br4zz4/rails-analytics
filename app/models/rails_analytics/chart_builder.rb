# frozen_string_literal: true

module RailsAnalytics
  # SVG line chart. Server-rendered, zero JS.
  class ChartBuilder
    WIDTH = 800
    HEIGHT = 220
    PAD = 8
    RIGHT_PAD = 40

    def initialize(series)
      @series = series # Array<Hash> with :date and :count
    end

    def build
      return empty_chart if @series.empty?

      max = [@series.map { |s| s[:count] }.max.to_f, 1].max
      points = @series.map.with_index do |s, i|
        x = pad(i)
        y = HEIGHT - PAD - ((s[:count] / max) * (HEIGHT - PAD * 2)).round
        "#{x.round(2)},#{y.round(2)}"
      end.join(" ")

      <<~SVG
        <svg viewBox="0 0 #{WIDTH + RIGHT_PAD} #{HEIGHT}" role="img" aria-label="#{I18n.t('rails_analytics.chart.visits_per_day')}" xmlns="http://www.w3.org/2000/svg">
          <polyline points="#{points}" fill="none" stroke="var(--ra-accent, #3b82f6)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
          #{dots(points)}
        </svg>
      SVG
    end

    private

    def pad(index)
      PAD + index * ((WIDTH - PAD) / [@series.length - 1, 1].max.to_f)
    end

    def dots(points_str)
      points_str.split(" ").map do |pt|
        x, y = pt.split(",")
        %(<circle cx="#{x}" cy="#{y}" r="3" fill="var(--ra-accent, #3b82f6)" />)
      end.join
    end

    def empty_chart
      <<~SVG
        <svg viewBox="0 0 #{WIDTH} #{HEIGHT}" role="img" xmlns="http://www.w3.org/2000/svg">
          <text x="#{WIDTH / 2}" y="#{HEIGHT / 2}" text-anchor="middle" fill="var(--ra-muted, #6b7280)">#{I18n.t('rails_analytics.chart.no_data')}</text>
        </svg>
      SVG
    end
  end
end