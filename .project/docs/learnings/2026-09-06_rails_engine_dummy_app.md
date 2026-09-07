# Rails Engine dummy app: 9 lessons from building rails_analytics v1

**Date:** 2026-09-06

## 1. Engine migrations are not auto-discovered by the dummy app

**Context:** While building the `rails_analytics` Rails Engine gem, `bin/rails db:migrate` inside `test/dummy` did not apply the engine's `db/migrate/` migrations.

**Learning:** Rails 8.1 only merges engine `db/migrate` when running rake from the engine root (`ENGINE_ROOT` set). Running `bin/rails` from the dummy only uses `test/dummy/db/migrate`. Each engine migration must be COPIED into `test/dummy/db/migrate/` with its own timestamp (this was already the pilot's pattern).

**Future application:** Any Rails Engine gem with migrations and a dummy app must maintain dual migration files (engine root + dummy copy). Consider a rake task to automate the copy.

## 2. `t.jsonb` breaks on the SQLite adapter

**Context:** The dummy app runs SQLite; production targets PostgreSQL. The events migration used `t.jsonb`.

**Learning:** `jsonb` raises `NoMethodError` on SQLite. Make the column type conditional: `jsonb` when `adapter_name == "PostgreSQL"`, `json` otherwise. GIN indexes are also PG-only and must be conditional.

**Future application:** Any engine supporting multiple DBs must guard PG-specific types and indexes.

## 3. `navigator.sendBeacon` does not accept custom headers

**Context:** The cookie-less tracker needs to authenticate the collect endpoint, but `sendBeacon` cannot set `Authorization: Bearer <token>`.

**Learning:** Accept the signed token in the JSON body (`{ token: ... }`) as well as the header. The controller validates either source. This preserves sendBeacon's guarantee of surviving page unload.

**Future application:** Any analytics/telemetry endpoint accepting sendBeacon must design token transport through the body.

## 4. Rails cross-origin JS protection returns 422

**Context:** The collect endpoint (POST JSON) returned 422 until `skip_before_action :verify_authenticity_token` was added.

**Learning:** The engine's collection controller must skip authenticity token verification (it validates its own signed token instead). The pilot had this; the v1 brief omitted it.

**Future application:** Public POST endpoints in an engine need an explicit auth strategy that replaces CSRF, and must skip `verify_authenticity_token`.

## 5. `ActiveSupport::MessageVerifier` is deterministic within a second

**Context:** Two signed tokens generated in the same second were identical (same signature), failing a "fresh token per request" test.

**Learning:** `MessageVerifier#generate` has no nonce. Include `nonce: SecureRandom.hex(8)` in the payload to guarantee uniqueness.

**Future application:** Any short-lived signed token that must differ per request needs an explicit nonce.

## 6. Malformed JSON + inline `rescue {}` creates garbage data

**Context:** The original controller used `json = JSON.parse(request.body.read) rescue {}`. Malformed payloads silently continued with `{}` and created an empty visit.

**Learning:** To honor "respond 204 without persisting on malformed payload", let the parse exception propagate to the method-level rescue (which responds 204 without saving). Remove inline rescues that mask bad input.

**Future application:** Collection endpoints should treat malformed input as no-op, not as empty payload.

## 7. Rack::Attack throttling needs a real cache store in tests

**Context:** Rate-limit tests passed 20+ requests without triggering 429.

**Learning:** `config.cache_store = :null_store` (some dummy defaults) makes Rack::Attack counters disappear. Use `:memory_store` in the test environment for throttling tests.

**Future application:** Any Rack::Attack throttling test must run with `:memory_store`.

## 8. `Date.today` vs `Time.current.to_date` — timezone flake

**Context:** A DailySalt test comparing "today vs yesterday" failed only near midnight UTC (app in UTC, system in UTC-3): `Date.current` was 07/09 while `Date.today` was still 06/09.

**Learning:** Tests comparing relative dates must use the app's timezone: `Time.current.to_date` and `Time.current.to_date - 1`, never `Date.today`/`Date.yesterday` mixed with `Time.current`.

**Future application:** Timezone-sensitive tests should derive dates from `Time.current`.

## 9. UA bucket OS regex order: iOS before macOS

**Context:** `Identity.coarse_ua_bucket` returned `Safari:macOS` for iPhone Safari UAs.

**Learning:** The `Mac OS X|macOS` regex matches before `iPhone|iPad|iOS` (iPhone UAs contain "Mac OS X" in the platform string). Check iOS before macOS when extracting coarse device OS.

**Future application:** Regex-based UA parsing must order most-specific (iOS) before generic (macOS).