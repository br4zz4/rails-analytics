# frozen_string_literal: true

module RailsAnalytics
  # Constrói o SVG do gráfico de barras (últimos 30 dias) no servidor — zero JS.
  class ChartBuilder
    WIDTH = 800
    HEIGHT = 220
    PAD = 8

    def initialize(series)
      @series = series
    end

    def build
      max = [@series.map { |s| s[:count] }.max.to_f, 1].max
      bar_w = (WIDTH - PAD * 2) / @series.length.to_f

      bars = @series.map.with_index do |s, i|
        h = ((s[:count] / max) * (HEIGHT - PAD * 2)).round
        x = (PAD + i * bar_w).round(2)
        y = (HEIGHT - PAD - h).round(2)
        %(<rect x="#{x}" y="#{y}" width="#{(bar_w - 2).round(2)}" height="#{[h, 1].max}" rx="2" data-day="#{s[:date]}" data-count="#{s[:count]}" />)
      end.join

      <<~SVG
        <svg viewBox="0 0 #{WIDTH} #{HEIGHT}" role="img" aria-label="Visitas por dia (últimos 30 dias)" xmlns="http://www.w3.org/2000/svg">
          #{bars}
        </svg>
      SVG
    end
  end
end