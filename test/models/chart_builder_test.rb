# frozen_string_literal: true

require "test_helper"

module RailsAnalytics
  class ChartBuilderTest < ActiveSupport::TestCase
    def build_chart
      series = [
        { date: Date.new(2026, 8, 28), count: 10 },
        { date: Date.new(2026, 9, 1), count: 40 },
        { date: Date.new(2026, 9, 2), count: 90 },
        { date: Date.new(2026, 9, 30), count: 20 }
      ]
      ChartBuilder.new(series).build
    end

    test "renders nodes with css-only tooltip structure" do
      svg = build_chart

      assert_includes svg, 'class="ra-dot"'
      assert_includes svg, 'tabindex="0"'
      assert_includes svg, "aria-label="
      assert_includes svg, 'class="ra-dot-circle"'
      assert_includes svg, 'class="ra-tooltip"'
      assert_includes svg, 'fill="transparent"' # hit area
      refute_includes svg.downcase, "<script"
    end

    test "tooltip label contains date and visit count" do
      svg = build_chart
      I18n.with_locale(:"pt-BR") do
        svg = ChartBuilder.new([{ date: Date.new(2026, 9, 2), count: 1234 }]).build
        # Delimiter matches number_with_delimiter used dashboard-wide
        assert_includes svg, "02/09 — 1,234 visitas"
      end
    end

    test "hit area is larger than the visible dot and captures pointer" do
      svg = build_chart
      assert ChartBuilder::HIT_RADIUS > ChartBuilder::DOT_RADIUS
      assert_match(/r="#{ChartBuilder::DOT_RADIUS}" class="ra-dot-circle"/, svg)
      # WebKit does not hit-test transparent fills with default pointer-events
      assert_match(/r="12" fill="transparent" pointer-events="all"/, svg)
    end

    test "renders x-axis labels for first and last point" do
      svg = build_chart

      # first + month boundary (01/09 fits between the ends) + last = 3
      assert_equal 3, svg.scan("ra-axis-label").size
      # first label anchored at start, last at end
      assert_includes svg, 'text-anchor="start"'
      assert_includes svg, 'text-anchor="end"'
    end

    test "month boundary label only when it fits between neighbours" do
      # 2026-09-01 is a month boundary and sits far from both ends
      series = [
        { date: Date.new(2026, 8, 1), count: 5 },
        { date: Date.new(2026, 9, 1), count: 10 },
        { date: Date.new(2026, 10, 1), count: 8 }
      ]
      svg = ChartBuilder.new(series).build

      assert_equal 3, svg.scan("ra-axis-label").size
    end

    test "skips month labels that would collide with ends" do
      # all points in one month: no middle label beyond first/last
      series = [
        { date: Date.new(2026, 9, 1), count: 5 },
        { date: Date.new(2026, 9, 15), count: 10 }
      ]
      svg = ChartBuilder.new(series).build

      assert_equal 2, svg.scan("ra-axis-label").size
    end

    test "single point renders without axis and with dot" do
      svg = ChartBuilder.new([{ date: Date.new(2026, 9, 1), count: 7 }]).build

      refute_includes svg, "ra-axis-label"
      assert_includes svg, "ra-dot"
    end

    test "empty series renders no-data message" do
      svg = ChartBuilder.new([]).build

      assert_includes svg, "Sem dados"
      refute_includes svg, "ra-dot"
    end
  end
end
