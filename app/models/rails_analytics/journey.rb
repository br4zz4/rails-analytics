# frozen_string_literal: true

module RailsAnalytics
  # Serializes a Visit (session) into a user journey: ordered steps with
  # kind/label/detail, plus origin and context metadata for the card header.
  class Journey
    def initialize(visit)
      @visit = visit
    end

    def to_h
      {
        id: @visit.id,
        origin: origin,
        device: @visit.device_type,
        viewport: @visit.viewport,
        language: @visit.language,
        utm: utm,
        started_at: @visit.started_at,
        duration: duration,
        steps: steps
      }
    end

    private

    def origin
      @visit.referrer_domain.presence || "direct"
    end

    def utm
      {
        source: @visit.utm_source,
        campaign: @visit.utm_campaign,
        medium: @visit.utm_medium
      }.compact
    end

    def duration
      last = @visit.events.map(&:time).max || @visit.started_at
      (last - @visit.started_at).to_i
    end

    # Ordered: landing page first, then tracked events by time.
    def steps
      sorted = @visit.events.sort_by(&:time)
      [pageview_step] + sorted.map { |event| event_step(event) }
    end

    def pageview_step
      {
        kind: :pageview,
        label: @visit.landing_page_path.to_s.split("?").first.presence || "/",
        detail: pageview_detail,
        time: @visit.started_at
      }
    end

    def pageview_detail
      parts = [I18n.t("rails_analytics.journeys.devices.#{@visit.device_type}", default: @visit.device_type)]
      parts << I18n.t("rails_analytics.journeys.details.viewport", value: @visit.viewport) if @visit.viewport.present?
      parts << I18n.t("rails_analytics.journeys.details.language", value: @visit.language) if @visit.language.present?
      parts.join(" · ")
    end

    def event_step(event)
      props = event.properties.is_a?(Hash) ? event.properties.symbolize_keys : {}
      kind = kind_for(event.name)

      {
        kind: kind,
        label: label_for(event.name, kind, props),
        detail: detail_for(props),
        time: event.time
      }
    end

    def kind_for(name)
      case name
      when /outbound/ then :outbound
      when /email/ then :email
      when /scroll/ then :scroll
      when /form/ then :form
      when /time/ then :time
      when /click/ then :click
      else :other
      end
    end

    def label_for(name, kind, props)
      case kind
      when :click then props[:value].presence || name
      when :scroll then I18n.t("rails_analytics.journeys.steps.scroll", mark: props[:mark].to_i)
      when :outbound then props[:target].presence || name
      when :email then I18n.t("rails_analytics.journeys.steps.email")
      when :form then I18n.t("rails_analytics.journeys.steps.form", form: props[:form].to_s)
      when :time then I18n.t("rails_analytics.journeys.steps.time_on_page", seconds: props[:seconds].to_i)
      else props[:value].presence || name
      end
    end

    def detail_for(props)
      return if props.empty?

      props
        .reject { |_, value| value.blank? }
        .map { |key, value| "#{key}: #{value}" }
        .join(" · ")
    end
  end
end
