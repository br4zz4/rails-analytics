# frozen_string_literal: true

module RailsAnalytics
  module Stats
    module_function

    def visits_by_day(since: default_since)
      base_scope(since).group("date(started_at)")
                       .order("date(started_at)")
                       .count
                       .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
    end

    def unique_visitors_by_day(since: default_since)
      base_scope(since).group("date(started_at)")
                       .order("date(started_at)")
                       .distinct
                       .count(:anonymity_key)
                       .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
    end

    def total_visits(since: default_since)
      base_scope(since).count
    end

    def total_unique_visitors(since: default_since)
      base_scope(since).distinct.count(:anonymity_key)
    end

    def total_events(since: default_since)
      Event.since(since).count
    end

    def top_sources(limit: 10, since: default_since)
      base_scope(since).where.not(referrer_domain: nil)
                       .group(:referrer_domain)
                       .order("count_all desc")
                       .limit(limit)
                       .count
    end

    def top_events(limit: 10, since: default_since)
      Event.since(since).group(:name)
           .order("count_all desc")
           .limit(limit)
           .count
    end

    def event_counts_by_name(since: default_since)
      Event.since(since).group(:name).count
    end

    def events_by_name(name, since: default_since)
      Event.since(since).named(name)
           .group("date(time)")
           .order("date(time)")
           .count
           .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
    end

    def bounce_rate(since: default_since)
      total = base_scope(since).count
      return 0.0 if total.zero?

      visits_with_events = base_scope(since)
                            .joins(:events)
                            .distinct
                            .count
      bounced = total - visits_with_events
      (bounced.to_f / total).round(4)
    end

    def devices(since: default_since)
      base_scope(since).group(:device_type).count
    end

    def utm_breakdown(since: default_since)
      base_scope(since).where.not(utm_source: nil).or(Visit.where.not(utm_campaign: nil))
                       .group(:utm_source, :utm_campaign, :utm_medium, :utm_term, :utm_content)
                       .count
                       .map do |keys, count|
        { "utm_source" => keys[0], "utm_campaign" => keys[1], "utm_medium" => keys[2],
          "utm_term" => keys[3], "utm_content" => keys[4], "count" => count }
      end
    end

    def visits_paginated(page: 1, per_page: 20, since: default_since)
      base = base_scope(since)
      total = base.count

      day_rows = base.group("date(started_at)")
                     .order("date(started_at) desc")
                     .select(
                       "date(started_at) as day",
                       "count(*) as visits",
                       "count(distinct anonymity_key) as unique_visitors"
                     )
                     .offset((page - 1) * per_page)
                     .limit(per_page)

      top_sources = base.where.not(referrer_domain: nil)
                        .group("date(started_at)", :referrer_domain)
                        .count

      data = day_rows.map do |row|
        day = row.day.to_date
        sources = top_sources.select { |(d, _ref), _count| d.to_date == day }
                             .max_by { |(_d, _ref), count| count }
        {
          date: day,
          visits: row.visits,
          unique_visitors: row.unique_visitors,
          top_source: sources&.first&.last
        }
      end

      { data: data, total: total, page: page, per_page: per_page }
    end

    def events_paginated(name: nil, page: 1, per_page: 20, since: default_since)
      scope = Event.since(since)
      scope = scope.named(name) if name.present?

      total = scope.group("date(time)", :name).count.size
      rows = scope.group("date(time)", :name)
                  .order("date(time) desc")
                  .select("date(time) as day, name, count(*) as count")
                  .offset((page - 1) * per_page)
                  .limit(per_page)

      data = rows.map do |r|
        { date: r.day.to_date, name: r.name, count: r.count }
      end

      { data: data, total: total, page: page, per_page: per_page }
    end

    def base_scope(since)
      Visit.since(since)
    end

    def default_since
      RailsAnalytics.config.since_default.ago
    end
  end
end