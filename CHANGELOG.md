# Changelog

## 1.0.3 (2026-09-07)

- Docs: standardize mount_path examples on `/analytics` (README + install template)

## 1.0.2 (2026-09-07)

- Fix: dashboard CSS now uses the engine route helper (`rails_analytics.dashboard_css_path`)
  instead of a hardcoded `/rails_analytics` prefix — fixes 404 when mounted at a custom path

## 1.0.1 (2026-09-07)

- Add gemspec metadata URIs (homepage, source, changelog, docs, bug tracker) for the rubygems.org page

## 1.0.0 (2026-09-06)

- Complete rewrite from pilot v0.1.0
- New: Visits + Events data model (replaces PageView)
- New: Cookie-less tracker JS with signed token + sendBeacon
- New: IP masking (IPv4 last octet, IPv6 last 80 bits)
- New: Identity key with coarse UA bucket + daily salt rotation
- New: Aggregated Stats module (14 query methods)
- New: Dashboard with 3 views (overview, events, visits)
- New: I18n support (pt-BR + en)
- New: Configurable auth callback (Symbol or callable)
- New: UTM parameter extraction at insert time
- New: RetentionJob (6-month purge, Marco Civil art. 15)
- New: Install generator with importmap pinning
- Ported: ChartBuilder (bar → line chart), CSS (extended)
- Removed: PageView model, pixel GIF endpoint, localStorage session

## 0.1.0 (2026-09-06)

- Pilot: pixel GIF collection, PageView model, SVG bar chart dashboard