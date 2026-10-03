# frozen_string_literal: true

module RailsAnalytics
  # SVG line chart. Server-rendered, zero JS.
  #
  # Each data point renders as a focusable group containing the visible dot,
  # a larger invisible hit area and a CSS-only tooltip (shown on :hover and
  # :focus). X-axis labels mark the first and last point plus month boundaries.
  class ChartBuilder
    WIDTH = 800
    HEIGHT = 220
    PAD = 8
    RIGHT_PAD = 40
    DOT_RADIUS = 3
    HIT_RADIUS = 12

    # Tooltip geometry. The tooltip is part of the SVG (server-computed),
    # revealed purely with CSS on :hover/:focus — no JavaScript involved.
    TOOLTIP_WIDTH = 130
    TOOLTIP_HEIGHT = 30
    TOOLTIP_OFFSET = 10

    # Plot area keeps HEIGHT; the viewBox gains a strip for x-axis labels.
    AXIS_PAD = 20

    # Minimum horizontal gap (px) between x-axis labels.
    AXIS_MIN_GAP = 70

    def initialize(series)
      @series = series # Array<Hash> with :date and :count
    end

    def build
      return empty_chart if @series.empty?

      max = [@series.map { |s| s[:count] }.max.to_f, 1].max
      nodes = @series.map.with_index { |s, i| dot_node(s, i, max) }.join("\n")

      <<~SVG
        <svg viewBox="0 0 #{WIDTH + RIGHT_PAD} #{HEIGHT + AXIS_PAD}" role="img" aria-label="#{I18n.t('rails_analytics.chart.visits_per_day')}" xmlns="http://www.w3.org/2000/svg">
          <polyline points="#{points(max)}" fill="none" stroke="var(--ra-accent, #3b82f6)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
          #{axis_labels}
          #{nodes}
        </svg>
      SVG
    end

    private

    def points(max)
      @series.each_with_index.map do |s, i|
        "#{x(i).round(2)},#{y(s[:count], max).round(2)}"
      end.join(" ")
    end

    def dot_node(series, index, max)
      cx = x(index).round(2)
      cy = y(series[:count], max).round(2)
      label = tooltip_text(series)

      <<~NODE.strip
        <g class="ra-dot" tabindex="0" role="img" aria-label="#{label}">
          <circle cx="#{cx}" cy="#{cy}" r="#{HIT_RADIUS}" fill="transparent" pointer-events="all" />
          <circle cx="#{cx}" cy="#{cy}" r="#{DOT_RADIUS}" class="ra-dot-circle" />
          #{tooltip(cx, cy, label)}
        </g>
      NODE
    end

    def tooltip(cx, cy, label)
      # Above the dot; flips to the far side when it would clip the top edge.
      tx = (cx - TOOLTIP_WIDTH / 2).clamp(0, WIDTH + RIGHT_PAD - TOOLTIP_WIDTH)
      ty = cy - DOT_RADIUS - TOOLTIP_OFFSET - TOOLTIP_HEIGHT
      ty = cy + DOT_RADIUS + TOOLTIP_OFFSET if ty < 0

      <<~TOOLTIP.strip
        <g class="ra-tooltip">
          <rect x="#{tx}" y="#{ty}" width="#{TOOLTIP_WIDTH}" height="#{TOOLTIP_HEIGHT}" rx="6" />
          <text x="#{tx + TOOLTIP_WIDTH / 2}" y="#{ty + TOOLTIP_HEIGHT / 2 + 4}" text-anchor="middle">#{label}</text>
        </g>
      TOOLTIP
    end

    def tooltip_text(series)
      I18n.t("rails_analytics.chart.tooltip", count: series[:count],
             date: series[:date].strftime(I18n.t("rails_analytics.chart.date_format")),
             formatted_count: ActiveSupport::NumberHelper.number_to_delimited(series[:count]))
    end

    def x(index)
      PAD + index * ((WIDTH - PAD) / [@series.length - 1, 1].max.to_f)
    end

    def y(count, max)
      HEIGHT - PAD - ((count / max) * (HEIGHT - PAD * 2))
    end

    # X-axis labels: first and last point always; month boundaries in between
    # only when far enough from the neighbouring label to avoid collision.
    def axis_labels
      return "" if @series.length < 2

      axis_indices.map do |i|
        anchor = "start" if i.zero?
        anchor = "end" if i == @series.length - 1
        anchor ||= "middle"
        %(<text x="#{x(i).round(2)}" y="#{HEIGHT + 13}" class="ra-axis-label" text-anchor="#{anchor}">#{write_date(@series[i][:date])}</text>)
      end.join("\n")
    end

    def axis_indices
      last = @series.length - 1
      kept = [0]
      (1...last).each do |i|
        next unless @series[i][:date].day == 1 # month boundary

        left_gap = x(i) - x(kept.last)
        right_gap = x(last) - x(i)
        kept << i if left_gap >= AXIS_MIN_GAP && right_gap >= AXIS_MIN_GAP
      end
      kept << last
      kept.uniq
    end

    def write_date(date)
      date.strftime(I18n.t("rails_analytics.chart.date_format"))
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
