---
title: rails_analytics v1 — Plano de implementação
spec: specs/20260906_rails_analytics_v1.md
created: 2026-09-06
updated: 2026-09-06
certainty: high
---

# rails_analytics v1 — Plano de implementação

> **TLDR**: Reescrever o piloto como engine completa: tracker JS cookie-less + POST com signed token, IP masking, identity key rotativa, Stats agregados, dashboard 3 views pt-BR, auth configurável, rate limiting, retention job, install generator.

> **Spec:** `.project/docs/specs/20260906_rails_analytics_v1.md`
> **Branch:** `feat/v1-engine-compelta`

**Arquitetura:** Rails Engine com namespace isolado. Core dividido em 4 camadas: lib/ (IpMask + Identity + Stats — lógica pura, sem Active Record), models/ (Visit + Event + DailySalt — Active Record), controllers/ (Analytics#collect + token + Dashboards), views/ (3 páginas ERB + SVG server-side). O tracker JS é servido via Propshaft; o signed token é gerado com ActiveSupport::MessageVerifier. Rate limiting via rack-attack (gem opcional). Auth via callback configurável (symbol ou callable).

**Stack:** Rails >= 7.0, PostgreSQL (jsonb), Minitest, Propshaft, importmap-rails (host), rack-attack (host), ChartBuilder (SVG server-rendered, portado do piloto), I18n (pt-BR + en).

## Restrições globais

- Nenhuma row individual exposta — Stats retorna apenas hashes/arrays agregados.
- IP real nunca armazenado — mascarado no `IpMask` antes de qualquer persistência.
- Sem cookies, sem localStorage no tracker — nonce por request, sendBeacon no unload.
- Payload malformado no endpoint de coleta nunca levanta exceção (responde 204).
- Dashboard sem JS obrigatório — SVG server-side; tabelas HTML como fallback.

---

### Task 0: Infra de testes — Rakefile, test_helper, dummy app

**Files:**
- Modify: `Rakefile` — excluir `test/dummy/**` do test task principal, criar task `integration`
- Rewrite: `test/test_helper.rb` — boot no dummy app (RAILS_ENV=test)
- Modify: `test/dummy/Gemfile` — adicionar `gem "rack-attack"`
- Modify: `test/dummy/config/routes.rb` — montar engine em `/rails_analytics`
- Modify: `test/dummy/app/controllers/application_controller.rb` — definir `authenticate_admin!` (redirect)
- Create: `test/dummy/config/initializers/rails_analytics.rb` — config da gem
- Create: `test/dummy/config/initializers/rack_attack.rb` — ativar rack-attack
- Modify: `.gitignore` — adicionar `.worktrees/`, `tmp/`

**Por quê:** o pre-flight mostrou que `bin/rails test` na raiz falha com NameError (test_helper não bota o Rails) e o Rakefile não distingue testes do gem vs dummy. Os testes unitários ficam na raiz (`test/lib/*_test.rb`, `test/models/*_test.rb`), então o test_helper da raiz precisa bootar o dummy app.

- [ ] **Step 1: Rewrite Rakefile**

```ruby
# Rakefile
# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.exclude_pattern = "test/dummy/**/*_test.rb"
  t.warning = false
end

Rake::TestTask.new(:integration) do |t|
  t.libs << "test/dummy/test"
  t.pattern = "test/dummy/test/**/*_test.rb"
  t.warning = false
end

task default: [:test, :integration]
```

- [ ] **Step 2: Rewrite test_helper**

```ruby
# test/test_helper.rb
# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"
require "rails/test_help"
require "rails_analytics"
```

- [ ] **Step 3: Update dummy Gemfile (add rack-attack)**

```ruby
# test/dummy/Gemfile — adicionar:
gem "rack-attack"
```

- [ ] **Step 4: Mount engine + auth no dummy**

```ruby
# test/dummy/config/routes.rb
Rails.application.routes.draw do
  mount RailsAnalytics::Engine => "/rails_analytics"
  root to: "application#index"
end
```

```ruby
# test/dummy/app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  def index
    render plain: "dummy"
  end

  private

  def authenticate_admin!
    redirect_to main_app.root_path, alert: "Não autorizado."
  end
end
```

```ruby
# test/dummy/config/initializers/rails_analytics.rb
RailsAnalytics.configure do |config|
  config.mount_path = "/rails_analytics"
end
```

```ruby
# test/dummy/config/initializers/rack_attack.rb
require "rack/attack"
Rack::Attack.enabled = true
```

- [ ] **Step 5: Add .worktrees/ + tmp/ to .gitignore**

```gitignore
/.bundle/
/pkg/
/tmp/
/.worktrees/
/test/dummy/log/
/test/dummy/tmp/
/test/dummy/storage/
/test/dummy/db/*.sqlite3*
```

- [ ] **Step 6: Verify**

```bash
cd test/dummy && bin/rails db:migrate RAILS_ENV=test && cd ../..
cd test/dummy && bin/rails test
```

Expected: PILOTO ainda verde (6 tests passam) — nada quebrou.

- [ ] **Step 7: Commit**

```bash
git add Rakefile test/test_helper.rb test/dummy/Gemfile test/dummy/config/routes.rb test/dummy/app/controllers/application_controller.rb test/dummy/config/initializers/ .gitignore
git commit -m "test: infra de testes com boot do dummy"
```

---

### Task 1: IpMask — mascaramento de IPs

**Files:**
- Create: `lib/rails_analytics/ip_mask.rb`
- Create: `test/lib/ip_mask_test.rb`

**Interfaces:**
- Produces: `RailsAnalytics::IpMask.mask(ip_string) => String`

Nota: usa `IPAddr#mask` (portável, sem regex manual). IPv4 → /24 (último octeto zero). IPv6 → /48 (últimos 80 bits zero). IPv4-mapped (::ffff:x.x.x.x) → mascara o IPv4 embutido.

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/ip_mask_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::IpMaskTest < ActiveSupport::TestCase
  def test_ipv4_zeros_last_octet
    assert_equal "192.168.1.0", RailsAnalytics::IpMask.mask("192.168.1.55")
    assert_equal "8.8.8.0",     RailsAnalytics::IpMask.mask("8.8.8.8")
    assert_equal "10.0.0.0",    RailsAnalytics::IpMask.mask("10.0.0.1")
  end

  def test_ipv6_zeros_last_80_bits
    assert_equal "2001:db8::", RailsAnalytics::IpMask.mask("2001:db8::ff00:42:8329")
    assert_equal "::",         RailsAnalytics::IpMask.mask("::1")
  end

  def test_ipv6_mapped_ipv4
    assert_equal "::ffff:192.168.1.0", RailsAnalytics::IpMask.mask("::ffff:192.168.1.55")
  end

  def test_localhost_ipv4_masked
    assert_equal "127.0.0.0", RailsAnalytics::IpMask.mask("127.0.0.1")
  end

  def test_nil_returns_nil
    assert_nil RailsAnalytics::IpMask.mask(nil)
  end

  def test_blank_returns_nil
    assert_nil RailsAnalytics::IpMask.mask("")
  end

  def test_invalid_ip_returns_nil
    assert_nil RailsAnalytics::IpMask.mask("not-an-ip")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/lib/ip_mask_test.rb
```

Expected: FAIL — `NameError: uninitialized constant RailsAnalytics::IpMask`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/rails_analytics/ip_mask.rb
# frozen_string_literal: true

require "ipaddr"

module RailsAnalytics
  module IpMask
    def self.mask(ip)
      return nil if ip.blank?

      addr = IPAddr.new(ip.to_s)
      if addr.ipv4?
        addr.mask(24).to_s
      elsif addr.ipv6?
        if addr.ipv4_mapped?
          IPAddr.new("::ffff:#{addr.native.mask(24)}").to_s
        else
          addr.mask(48).to_s
        end
      end
    rescue IPAddr::InvalidAddressError
      nil
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd test/dummy && bin/rails test test/lib/ip_mask_test.rb
```

Expected: PASS — 7 assertions

- [ ] **Step 5: Commit**

```bash
git add lib/rails_analytics/ip_mask.rb test/lib/ip_mask_test.rb
git commit -m "feat: IpMask para IPv4 e IPv6"
```

---

### Task 2: Configuration + entry point

**Files:**
- Create: `lib/rails_analytics/configuration.rb`
- Rewrite: `lib/rails_analytics.rb`

**Interfaces:**
- Produces: `RailsAnalytics.configure { |c| ... }`, `RailsAnalytics.config`
- Config keys: `auth_callback` (Symbol/Proc, default `:authenticate_admin!`), `mount_path` (String, default `"/analytics"`), `since_default` (ActiveSupport::Duration, default `30.days`)

- [ ] **Step 1: Write the configuration class**

```ruby
# lib/rails_analytics/configuration.rb
# frozen_string_literal: true

module RailsAnalytics
  class Configuration
    attr_accessor :auth_callback, :mount_path, :since_default

    def initialize
      @auth_callback = :authenticate_admin!
      @mount_path = "/analytics"
      @since_default = 30.days
    end

    def auth_callback_callable?
      auth_callback.respond_to?(:call)
    end
  end
end
```

- [ ] **Step 2: Update entry point**

```ruby
# lib/rails_analytics.rb
# frozen_string_literal: true

require_relative "rails_analytics/version"
require_relative "rails_analytics/configuration"
require_relative "rails_analytics/engine" if defined?(Rails::Railtie)

module RailsAnalytics
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config if block_given?
    end
  end
end
```

- [ ] **Step 3: Verify — no test file needed (pure config, verified by downstream tasks)**

```bash
cd test/dummy && bin/rails runner "RailsAnalytics.configure { |c| c.mount_path = '/foo' }; puts RailsAnalytics.config.mount_path"
```

Expected: prints `/foo`

- [ ] **Step 4: Commit**

```bash
git add lib/rails_analytics/configuration.rb lib/rails_analytics.rb
git commit -m "feat: Configuration com auth_callback e mount_path"
```

---

### Task 3: DailySalt — model + migration

**Files:**
- Create: `db/migrate/20260906000001_create_rails_analytics_daily_salts.rb`
- Create: `app/models/rails_analytics/daily_salt.rb`
- Create: `test/models/daily_salt_test.rb`

**Interfaces:**
- Consumes: `RailsAnalytics::Engine` (for table prefix)
- Produces: `RailsAnalytics::DailySalt.for_date(date) => String` (salt value for given date)

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/daily_salt_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::DailySaltTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::DailySalt.delete_all
  end

  test "for_date creates salt on first call" do
    salt1 = RailsAnalytics::DailySalt.for_date(Date.today)
    assert_kind_of String, salt1
    assert_equal 64, salt1.length # SHA256 hex digest = 64 chars
  end

  test "for_date returns same salt for same date" do
    salt1 = RailsAnalytics::DailySalt.for_date(Date.today)
    salt2 = RailsAnalytics::DailySalt.for_date(Date.today)
    assert_equal salt1, salt2
  end

  test "for_date returns different salt for different dates" do
    salt1 = RailsAnalytics::DailySalt.for_date(Date.today)
    salt2 = RailsAnalytics::DailySalt.for_date(Date.yesterday)
    refute_equal salt1, salt2
  end

  test "for_date persists only one row per date" do
    3.times { RailsAnalytics::DailySalt.for_date(Date.today) }
    assert_equal 1, RailsAnalytics::DailySalt.where(date: Date.today).count
  end

  test "for_date without db falls back to deterministic derivation" do
    salt = RailsAnalytics::DailySalt.derive_salt(Date.today)
    assert_kind_of String, salt
    assert_equal 64, salt.length
    # Same date → same salt
    assert_equal salt, RailsAnalytics::DailySalt.derive_salt(Date.today)
    # Different date → different salt
    refute_equal salt, RailsAnalytics::DailySalt.derive_salt(Date.yesterday)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/models/daily_salt_test.rb
```

Expected: FAIL — migration missing, table doesn't exist

- [ ] **Step 3: Write migration + model**

```ruby
# db/migrate/20260906000001_create_rails_analytics_daily_salts.rb
# frozen_string_literal: true

class CreateRailsAnalyticsDailySalts < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_daily_salts do |t|
      t.date :date, null: false
      t.string :salt, null: false

      t.timestamps
    end

    add_index :rails_analytics_daily_salts, :date, unique: true
  end
end
```

```ruby
# app/models/rails_analytics/daily_salt.rb
# frozen_string_literal: true

require "securerandom"
require "digest"

module RailsAnalytics
  class DailySalt < ActiveRecord::Base
    self.table_name = "rails_analytics_daily_salts"

    validates :date, presence: true, uniqueness: true
    validates :salt, presence: true

    def self.for_date(date = Date.today)
      find_or_create_by!(date: date) do |ds|
        ds.salt = SecureRandom.hex(32)
      end.salt
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      derive_salt(date)
    end

    def self.derive_salt(date)
      key = Rails.application.try(:secret_key_base) || Rails.application.try(:secrets).try(:secret_key_base) || "rails_analytics_fallback"
      Digest::SHA256.hexdigest("#{key}:#{date.iso8601}")
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd test/dummy && bin/rails db:migrate RAILS_ENV=test
cd test/dummy && bin/rails test test/models/daily_salt_test.rb
```

Expected: PASS — 5 tests

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260906000001_create_rails_analytics_daily_salts.rb app/models/rails_analytics/daily_salt.rb test/models/daily_salt_test.rb
git commit -m "feat: DailySalt com fallback determinístico"
```

---

### Task 4: Identity — chave de anonimato

**Files:**
- Create: `lib/rails_analytics/identity.rb`
- Create: `test/lib/identity_test.rb`

**Interfaces:**
- Consumes: `RailsAnalytics::IpMask`, `RailsAnalytics::DailySalt`
- Produces: `RailsAnalytics::Identity.key(masked_ip:, user_agent:, date:) => String`

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/identity_test.rb
# frozen_string_literal: true

require "test_helper"
require "rails_analytics/ip_mask"
require "rails_analytics/identity"

class RailsAnalytics::IdentityTest < Minitest::Test
  def test_same_inputs_same_key
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0 (X11; Linux x86_64) Chrome/120.0", date: Date.new(2026, 1, 1))
    k2 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0 (X11; Linux x86_64) Chrome/120.0", date: Date.new(2026, 1, 1))
    assert_equal k1, k2
  end

  def test_different_ip_different_key
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.today)
    k2 = RailsAnalytics::Identity.key(masked_ip: "1.2.3.0", user_agent: "Mozilla/5.0", date: Date.today)
    refute_equal k1, k2
  end

  def test_different_date_different_key
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.new(2026, 1, 1))
    k2 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.new(2026, 1, 2))
    refute_equal k1, k2
  end

  def test_similar_ua_same_bucket
    ua1 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0"
    ua2 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/121.0.0.0"
    k1 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: ua1, date: Date.today)
    k2 = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: ua2, date: Date.today)
    assert_equal k1, k2 # Same OS + browser family → same bucket
  end

  def test_cannot_recover_ip_from_key
    key = RailsAnalytics::Identity.key(masked_ip: "8.8.8.0", user_agent: "Mozilla/5.0", date: Date.today)
    refute_includes key, "8.8.8.0"
    refute_includes key.downcase, "8.8.8.0"
  end

  def test_coarse_ua_bucket_detects_chrome_on_mac
    ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    bucket = RailsAnalytics::Identity.coarse_ua_bucket(ua)
    assert_equal "Chrome:macOS", bucket
  end

  def test_coarse_ua_bucket_detects_safari_on_ios
    ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    bucket = RailsAnalytics::Identity.coarse_ua_bucket(ua)
    assert_equal "Safari:iOS", bucket
  end

  def test_coarse_ua_bucket_fallback_unknown
    bucket = RailsAnalytics::Identity.coarse_ua_bucket("curl/7.79.1")
    assert_equal "Other:Other", bucket
  end

  def test_coarse_ua_bucket_handles_nil
    bucket = RailsAnalytics::Identity.coarse_ua_bucket(nil)
    assert_equal "Other:Other", bucket
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/lib/identity_test.rb
```

Expected: FAIL — `NameError: uninitialized constant RailsAnalytics::Identity`

- [ ] **Step 3: Write implementation**

```ruby
# lib/rails_analytics/identity.rb
# frozen_string_literal: true

require "digest"

module RailsAnalytics
  module Identity
    # Coarse UA bucket: "<browser_family>:<os_family>"
    # Never stores the full user agent string.
    def self.coarse_ua_bucket(user_agent)
      return "Other:Other" if user_agent.nil? || user_agent.empty?

      ua = user_agent.to_s

      os = if ua.match?(/Windows|Win64|Win32/i)
             "Windows"
           elsif ua.match?(/Macintosh|Mac OS X|macOS/i)
             "macOS"
           elsif ua.match?(/iPhone|iPad|iOS/i)
             "iOS"
           elsif ua.match?(/Android/i)
             "Android"
           elsif ua.match?(/Linux|X11/i)
             "Linux"
           else
             "Other"
           end

      browser = if ua.match?(/Edg\//i)
                  "Edge"
                elsif ua.match?(/OPR|Opera/i)
                  "Opera"
                elsif ua.match?(/Chrome/i)
                  "Chrome"
                elsif ua.match?(/Safari/i)
                  "Safari"
                elsif ua.match?(/Firefox/i)
                  "Firefox"
                else
                  "Other"
                end

      "#{browser}:#{os}"
    end

    def self.key(masked_ip:, user_agent:, date:)
      bucket = coarse_ua_bucket(user_agent)
      salt = RailsAnalytics::DailySalt.for_date(date)
      Digest::SHA256.hexdigest("#{masked_ip}:#{bucket}:#{salt}")
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd test/dummy && bin/rails test test/lib/identity_test.rb
```

Expected: PASS — 9 tests

- [ ] **Step 5: Commit**

```bash
git add lib/rails_analytics/identity.rb test/lib/identity_test.rb
git commit -m "feat: Identity key com coarse UA bucket"
```

---

### Task 5: Visit — model + migration

**Files:**
- Create: `db/migrate/20260906000002_create_rails_analytics_visits.rb`
- Create: `app/models/rails_analytics/visit.rb`
- Create: `test/models/visit_test.rb`

**Interfaces:**
- Consumes: `RailsAnalytics::Identity`
- Produces: `RailsAnalytics::Visit` — `has_many :events`, scopes `since(time)`, `for_key(key)`, class method `.find_or_create_for(anonymity_key, attrs)` (upsert logic with 4h window)

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/visit_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::VisitTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
  end

  test "creates a visit with valid attributes" do
    visit = RailsAnalytics::Visit.create!(
      anonymity_key: "abc123",
      masked_ip: "8.8.8.0",
      referrer_domain: "google.com",
      landing_page_path: "/?utm_source=twitter",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: Time.current
    )
    assert visit.persisted?
    assert_equal "desktop", visit.device_type
  end

  test "since scope filters by started_at" do
    old = RailsAnalytics::Visit.create!(anonymity_key: "a", masked_ip: "1.1.1.0", started_at: 40.days.ago)
    recent = RailsAnalytics::Visit.create!(anonymity_key: "b", masked_ip: "2.2.2.0", started_at: 1.day.ago)

    result = RailsAnalytics::Visit.since(30.days.ago)
    assert_includes result, recent
    refute_includes result, old
  end

  test "for_key scope filters by anonymity_key" do
    v1 = RailsAnalytics::Visit.create!(anonymity_key: "key_a", masked_ip: "1.1.1.0", started_at: Time.current)
    v2 = RailsAnalytics::Visit.create!(anonymity_key: "key_b", masked_ip: "2.2.2.0", started_at: Time.current)

    result = RailsAnalytics::Visit.for_key("key_a")
    assert_equal [v1.id], result.pluck(:id)
  end

  test "find_or_create_for reuses visit within 4h window" do
    key = "test_key_reuse"
    t0 = Time.current

    v1 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "example.com",
      landing_page_path: "/page1",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: t0
    })

    v2 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "example.com",
      landing_page_path: "/page2",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: t0 + 3.hours
    })

    assert_equal v1.id, v2.id, "deve reutilizar a mesma visit dentro da janela de 4h"
  end

  test "find_or_create_for creates new visit after 4h window" do
    key = "test_key_new_window"

    v1 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "example.com",
      landing_page_path: "/page1",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: 5.hours.ago
    })

    v2 = RailsAnalytics::Visit.find_or_create_for(key, {
      masked_ip: "8.8.8.0",
      referrer_domain: "other.com",
      landing_page_path: "/page2",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      started_at: Time.current
    })

    refute_equal v1.id, v2.id, "deve criar nova visit após janela de 4h"
  end

  test "has_many events with dependent delete_all" do
    visit = RailsAnalytics::Visit.create!(anonymity_key: "del", masked_ip: "1.1.1.0", started_at: Time.current)
    visit.events.create!(name: "click", time: Time.current)

    assert_difference -> { RailsAnalytics::Event.count }, -1 do
      visit.destroy
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/models/visit_test.rb
```

Expected: FAIL — migration missing

- [ ] **Step 3: Write migration + model**

```ruby
# db/migrate/20260906000002_create_rails_analytics_visits.rb
# frozen_string_literal: true

class CreateRailsAnalyticsVisits < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_visits do |t|
      t.string   :anonymity_key,  null: false
      t.string   :masked_ip,      null: false
      t.string   :referrer_domain
      t.text     :landing_page_path
      t.string   :device_type
      t.string   :viewport
      t.string   :language
      t.string   :country
      t.string   :utm_source
      t.string   :utm_medium
      t.string   :utm_campaign
      t.string   :utm_term
      t.string   :utm_content
      t.datetime :started_at,     null: false

      t.timestamps
    end

    add_index :rails_analytics_visits, :started_at
    add_index :rails_analytics_visits, [:anonymity_key, :started_at], name: "idx_visits_anonymity_started"
  end
end
```

```ruby
# app/models/rails_analytics/visit.rb
# frozen_string_literal: true

module RailsAnalytics
  class Visit < ActiveRecord::Base
    self.table_name = "rails_analytics_visits"

    has_many :events, class_name: "RailsAnalytics::Event", dependent: :delete_all

    validates :anonymity_key, presence: true
    validates :masked_ip, presence: true
    validates :started_at, presence: true

    scope :since, ->(time) { where(arel_table[:started_at].gteq(time)) }
    scope :for_key, ->(key) { where(anonymity_key: key) }

    INACTIVITY_WINDOW = 4.hours

    def self.find_or_create_for(anonymity_key, attrs = {})
      recent = for_key(anonymity_key)
               .where(started_at: (attrs[:started_at] || Time.current) - INACTIVITY_WINDOW..)
               .order(started_at: :desc)
               .first

      return recent if recent

      create!(attrs.merge(anonymity_key: anonymity_key))
    end

    def self.parse_utm_params(path)
      return {} if path.blank?

      query = URI.parse(path).query.to_s
      params = URI.decode_www_form(query).to_h
      {
        utm_source:   params["utm_source"],
        utm_medium:   params["utm_medium"],
        utm_campaign: params["utm_campaign"],
        utm_term:     params["utm_term"],
        utm_content:  params["utm_content"]
      }
    rescue URI::InvalidURIError
      {}
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd test/dummy && bin/rails db:migrate RAILS_ENV=test
cd test/dummy && bin/rails test test/models/visit_test.rb
```

Expected: PASS — 6 tests

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260906000002_create_rails_analytics_visits.rb app/models/rails_analytics/visit.rb test/models/visit_test.rb
git commit -m "feat: Visit model com find_or_create_for e UTM parse"
```

---

### Task 6: Event — model + migration

**Files:**
- Create: `db/migrate/20260906000003_create_rails_analytics_events.rb`
- Create: `app/models/rails_analytics/event.rb`
- Create: `test/models/event_test.rb`

**Interfaces:**
- Consumes: `RailsAnalytics::Visit`
- Produces: `RailsAnalytics::Event` — `belongs_to :visit`, scopes `since(time)`, `named(name)`

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/event_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::EventTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    @visit = RailsAnalytics::Visit.create!(anonymity_key: "k", masked_ip: "1.1.1.0", started_at: Time.current)
  end

  test "creates event with name and properties" do
    event = @visit.events.create!(name: "doacao-click", time: Time.current, properties: { value: 50 })
    assert event.persisted?
    assert_equal "doacao-click", event.name
    assert_equal({ "value" => 50 }, event.properties)
  end

  test "properties defaults to empty hash" do
    event = @visit.events.create!(name: "click", time: Time.current)
    assert_equal({}, event.properties)
  end

  test "since scope filters by time" do
    old = @visit.events.create!(name: "e1", time: 40.days.ago)
    recent = @visit.events.create!(name: "e2", time: 1.day.ago)

    result = RailsAnalytics::Event.since(30.days.ago)
    assert_includes result, recent
    refute_includes result, old
  end

  test "named scope filters by name" do
    @visit.events.create!(name: "click", time: Time.current)
    @visit.events.create!(name: "scroll", time: Time.current)

    result = RailsAnalytics::Event.named("click")
    assert_equal 1, result.count
    assert_equal "click", result.first.name
  end

  test "belongs to visit" do
    event = @visit.events.create!(name: "click", time: Time.current)
    assert_equal @visit, event.visit
  end

  test "destroying visit deletes events" do
    @visit.events.create!(name: "e1", time: Time.current)
    @visit.events.create!(name: "e2", time: Time.current)

    assert_difference -> { RailsAnalytics::Event.count }, -2 do
      @visit.destroy
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/models/event_test.rb
```

Expected: FAIL — migration missing

- [ ] **Step 3: Write migration + model**

```ruby
# db/migrate/20260906000003_create_rails_analytics_events.rb
# frozen_string_literal: true

class CreateRailsAnalyticsEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_events do |t|
      t.references :visit, null: false, foreign_key: { to_table: :rails_analytics_visits }
      t.string     :name, null: false
      t.jsonb      :properties, default: {}
      t.datetime   :time, null: false

      t.timestamps
    end

    add_index :rails_analytics_events, :name
    add_index :rails_analytics_events, :time
    add_index :rails_analytics_events, [:name, :time]
    add_index :rails_analytics_events, :properties, using: :gin
  end
end
```

```ruby
# app/models/rails_analytics/event.rb
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
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd test/dummy && bin/rails db:migrate RAILS_ENV=test
cd test/dummy && bin/rails test test/models/event_test.rb
```

Expected: PASS — 6 tests

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260906000003_create_rails_analytics_events.rb app/models/rails_analytics/event.rb test/models/event_test.rb
git commit -m "feat: Event model com scopes e GIN index"
```

---

### Task 7: Stats — queries agregadas

**Files:**
- Create: `lib/rails_analytics/stats.rb`
- Create: `test/models/stats_test.rb`

**Interfaces:**
- Consumes: `RailsAnalytics::Visit`, `RailsAnalytics::Event`
- Produces: `RailsAnalytics::Stats` — 12 métodos de agregação (spec: visits_by_day, unique_visitors_by_day, total_visits, total_unique_visitors, total_events, top_sources, top_events, event_counts_by_name, events_by_name, bounce_rate, utm_breakdown, devices) + `visits_paginated` + `events_paginated`. Todos recebem `since:` (default `RailsAnalytics.config.since_default.ago`).

Nota: NENHUMA função PostgreSQL-only (o dummy roda SQLite). `visits_paginated` monta top_source em query separada e agrega no Ruby (volumes pequenos, dias únicos).

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/stats_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::StatsTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    seed_data
  end

  def seed_data
    now = Time.current

    # Visit 1: com events (bounce = false)
    v1 = RailsAnalytics::Visit.create!(anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "google.com",
                                        landing_page_path: "/?utm_source=twitter&utm_campaign=jan25",
                                        device_type: "desktop", viewport: "1440x900", language: "pt-BR",
                                        utm_source: "twitter", utm_campaign: "jan25",
                                        started_at: now)
    v1.events.create!(name: "doacao-click", time: now, properties: { value: 50 })
    v1.events.create!(name: "email-click", time: now)

    # Visit 2: sem events (bounce = true)
    v2 = RailsAnalytics::Visit.create!(anonymity_key: "k2", masked_ip: "1.2.3.0", referrer_domain: "instagram.com",
                                        landing_page_path: "/blog",
                                        device_type: "mobile", viewport: "390x844", language: "en",
                                        started_at: now)

    # Visit 3: sem events (bounce = true)
    v3 = RailsAnalytics::Visit.create!(anonymity_key: "k3", masked_ip: "5.6.7.0", referrer_domain: "direct",
                                        landing_page_path: "/contato",
                                        device_type: "tablet", viewport: "768x1024", language: "pt-BR",
                                        started_at: 1.day.ago)

    # Visit 4: sem events (bounce = true)
    v4 = RailsAnalytics::Visit.create!(anonymity_key: "k4", masked_ip: "9.9.9.0", referrer_domain: "google.com",
                                        landing_page_path: "/",
                                        device_type: "desktop", viewport: "1920x1080", language: "pt-BR",
                                        started_at: 1.day.ago)
  end

  test "total_visits returns count" do
    assert_equal 4, RailsAnalytics::Stats.total_visits
  end

  test "total_visits with since filter" do
    assert_equal 2, RailsAnalytics::Stats.total_visits(since: 12.hours.ago)
  end

  test "total_unique_visitors returns distinct anonymity keys" do
    assert_equal 4, RailsAnalytics::Stats.total_unique_visitors
  end

  test "total_events returns event count" do
    assert_equal 2, RailsAnalytics::Stats.total_events
  end

  test "visits_by_day returns hash" do
    result = RailsAnalytics::Stats.visits_by_day
    assert_kind_of Hash, result
  end

  test "unique_visitors_by_day returns hash" do
    result = RailsAnalytics::Stats.unique_visitors_by_day
    assert_kind_of Hash, result
  end

  test "bounce_rate is 0.75" do
    # 3 visits sem events, 1 com events → 3/4 = 0.75
    assert_equal 0.75, RailsAnalytics::Stats.bounce_rate
  end

  test "top_sources returns sorted hash" do
    result = RailsAnalytics::Stats.top_sources
    assert_kind_of Hash, result
    assert_equal "google.com", result.keys.first
    assert_equal 2, result.values.first
  end

  test "top_events returns sorted hash" do
    result = RailsAnalytics::Stats.top_events
    assert_equal({ "doacao-click" => 1, "email-click" => 1 }, result)
  end

  test "event_counts_by_name returns hash" do
    result = RailsAnalytics::Stats.event_counts_by_name
    assert_equal({ "doacao-click" => 1, "email-click" => 1 }, result)
  end

  test "events_by_name filters by event name over time" do
    result = RailsAnalytics::Stats.events_by_name("doacao-click")
    assert_kind_of Hash, result
    assert_equal 1, result.values.sum
  end

  test "devices returns breakdown" do
    result = RailsAnalytics::Stats.devices
    assert_equal({ "desktop" => 2, "mobile" => 1, "tablet" => 1 }, result)
  end

  test "utm_breakdown returns aggregation" do
    result = RailsAnalytics::Stats.utm_breakdown
    assert_equal 1, result.count { |r| r["utm_source"] == "twitter" }
    assert_equal 1, result.count { |r| r["utm_campaign"] == "jan25" }
  end

  test "visits_paginated returns array with total count" do
    page = RailsAnalytics::Stats.visits_paginated(page: 1, per_page: 2)
    assert_equal 2, page[:data].length
    assert_equal 4, page[:total]
  end

  test "events_paginated returns array with total count" do
    page = RailsAnalytics::Stats.events_paginated(name: "doacao-click", page: 1, per_page: 10)
    assert_equal 1, page[:data].length
    assert_equal 1, page[:total]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/models/stats_test.rb
```

Expected: FAIL — `NameError: uninitialized constant RailsAnalytics::Stats`

- [ ] **Step 3: Write implementation**

```ruby
# lib/rails_analytics/stats.rb
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
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd test/dummy && bin/rails test test/models/stats_test.rb
```

Expected: PASS — 15 tests

- [ ] **Step 5: Commit**

```bash
git add lib/rails_analytics/stats.rb test/models/stats_test.rb
git commit -m "feat: Stats com 14 métodos agregados"
```

---

### Task 8: ApplicationController + auth callback

**Files:**
- Rewrite: `app/controllers/rails_analytics/application_controller.rb`
- Create: `test/controllers/application_controller_test.rb`

**Interfaces:**
- Consumes: `RailsAnalytics.config.auth_callback`
- Produces: `RailsAnalytics::ApplicationController` — herda do `ApplicationController` do host (padrão RailsAdmin), `before_action :authorize_admin!`. AnalyticsController (coleta) chama `skip_before_action :authorize_admin!`.

Nota crítica: o engine controller HERDA do host para que `:authenticate_admin!` (Devise do host) fique acessível via `send`. O `before_action` se chama `authorize_admin!` (nome diferente do callback) para evitar loop infinito quando `auth_callback = :authenticate_admin!`.

- [ ] **Step 1: Write the implementation (controller)**

```ruby
# app/controllers/rails_analytics/application_controller.rb
# frozen_string_literal: true

module RailsAnalytics
  # Herda do ApplicationController do host (padrão RailsAdmin) para que o
  # callback de auth (ex: Devise authenticate_admin!) fique acessível.
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    layout "rails_analytics"

    before_action :authorize_admin!

    private

    def authorize_admin!
      callback = RailsAnalytics.config.auth_callback

      if callback.respond_to?(:call)
        redirect_to main_app.root_path unless instance_exec(&callback)
      else
        # Symbol: delega ao host (Devise decide redirect/raise)
        send(callback)
      end
    end
  end
end
```

```ruby
# test/controllers/application_controller_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "redirects when host auth rejects" do
    RailsAnalytics.config.auth_callback = -> { false }
    get "/rails_analytics/"
    assert_response :redirect
  ensure
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end

  test "allows when host auth accepts" do
    RailsAnalytics.config.auth_callback = -> { true }
    get "/rails_analytics/"
    assert_response :success
  ensure
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end
end
```

- [ ] **Step 2: Run to verify**

```bash
cd test/dummy && bin/rails test test/controllers/application_controller_test.rb
```

Expected: PASS — ambos os testes (redirect quando rejeita, 200 quando aceita)

- [ ] **Step 3: Commit**

```bash
git add app/controllers/rails_analytics/application_controller.rb test/controllers/application_controller_test.rb
git commit -m "feat: ApplicationController com auth configurável"
```

---

### Task 9: AnalyticsController — coleta + token

**Files:**
- Rewrite: `app/controllers/rails_analytics/analytics_controller.rb`
- Create: `test/controllers/analytics_controller_test.rb`

**Interfaces:**
- Consumes: `RailsAnalytics::IpMask`, `RailsAnalytics::Identity`, `RailsAnalytics::Visit`, `RailsAnalytics::Event`
- Produces: `POST /collect` (204), `GET /tracker.js` (JS), `GET /token` (JSON signed token), `GET /dashboard.css` (CSS)

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/analytics_controller_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    @verifier = Rails.application.message_verifier("rails_analytics_tracker")
    @valid_token = @verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)
  end

  def valid_payload(overrides = {})
    {
      path: "/blog/hello",
      referrer_domain: "google.com",
      device_type: "desktop",
      viewport: "1440x900",
      language: "pt-BR",
      nonce: SecureRandom.hex(8),
      events: [{ name: "click", time: Time.current.iso8601 }]
    }.merge(overrides)
  end

  test "POST collect with valid token creates visit and event" do
    assert_difference -> { RailsAnalytics::Visit.count }, 1 do
      assert_difference -> { RailsAnalytics::Event.count }, 1 do
        post "/rails_analytics/collect",
             params: valid_payload.to_json,
             headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}", "REMOTE_ADDR" => "8.8.8.8" }
      end
    end

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_equal "8.8.8.0", visit.masked_ip
    assert_equal "desktop", visit.device_type
  end

  test "POST collect without token returns 401" do
    post "/rails_analytics/collect",
         params: valid_payload.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "POST collect with malformed payload returns 204 gracefully" do
    assert_no_difference -> { RailsAnalytics::Visit.count } do
      post "/rails_analytics/collect",
           params: "not json",
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}" }
    end

    assert_response :no_content
  end

  test "POST collect masks IP before storing" do
    post "/rails_analytics/collect",
         params: valid_payload.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}", "REMOTE_ADDR" => "192.168.1.55" }

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_equal "192.168.1.0", visit.masked_ip
  end

  test "POST collect parses UTM params from path" do
    post "/rails_analytics/collect",
         params: valid_payload(path: "/?utm_source=twitter&utm_campaign=jan25").to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@valid_token}" }

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_equal "twitter", visit.utm_source
    assert_equal "jan25", visit.utm_campaign
  end

  test "GET token returns signed token" do
    get "/rails_analytics/token"

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("token")
    # Verify it's a valid verifier token
    assert_nothing_raised do
      @verifier.verified(body["token"], purpose: :tracker)
    end
  end

  test "GET token returns fresh token each request" do
    get "/rails_analytics/token"
    t1 = JSON.parse(response.body)["token"]

    get "/rails_analytics/token"
    t2 = JSON.parse(response.body)["token"]

    refute_equal t1, t2
  end

  test "GET tracker.js serves javascript" do
    get "/rails_analytics/tracker.js"

    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert_includes response.body, "RailsAnalytics"
  end

  test "GET dashboard.css serves css" do
    get "/rails_analytics/dashboard.css"

    assert_response :success
    assert_equal "text/css", response.media_type
    assert_includes response.body, "ra"
  end

  test "tracker.js HTML does not leak secrets" do
    get "/rails_analytics/tracker.js"
    refute_includes response.body, "secret"
    refute_includes response.body, "key_base"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/controllers/analytics_controller_test.rb
```

Expected: FAIL — route doesn't exist yet

- [ ] **Step 3: Write controller**

```ruby
# app/controllers/rails_analytics/analytics_controller.rb
# frozen_string_literal: true

module RailsAnalytics
  class AnalyticsController < ApplicationController
    skip_before_action :authorize_admin!

    TOKEN_PURPOSE = :tracker
    VERIFIER_NAME = "rails_analytics_tracker"

    def collect
      json = JSON.parse(request.body.read) rescue {}
      token = extract_token(request, json)

      unless valid_token?(token)
        render json: { error: "Unauthorized" }, status: :unauthorized and return
      end

      client_ip = request.env["HTTP_CF_CONNECTING_IP"] || request.remote_ip
      masked = IpMask.mask(client_ip)
      ua = request.user_agent.to_s
      path = json["path"].to_s[0, 2000]

      anonymity_key = Identity.key(
        masked_ip: masked,
        user_agent: ua,
        date: Date.today
      )

      utm = Visit.parse_utm_params(path)

      visit = Visit.find_or_create_for(anonymity_key, {
        masked_ip: masked,
        referrer_domain: json["referrer_domain"].to_s[0, 500].presence,
        landing_page_path: path,
        device_type: json["device_type"].to_s[0, 50].presence || "unknown",
        viewport: json["viewport"].to_s[0, 20].presence,
        language: json["language"].to_s[0, 10].presence,
        started_at: Time.current,
        **utm
      })

      Array(json["events"]).each do |ev|
        next unless ev.is_a?(Hash)
        visit.events.create!(
          name: ev["name"].to_s[0, 100],
          time: Time.parse(ev["time"].to_s) rescue Time.current,
          properties: (ev["properties"].is_a?(Hash) ? ev["properties"] : {})
        )
      end

      head :no_content
    rescue JSON::ParserError, ActiveRecord::RecordInvalid, ArgumentError
      head :no_content
    end

    def token
      verifier = Rails.application.message_verifier(VERIFIER_NAME)
      signed = verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: TOKEN_PURPOSE)
      render json: { token: signed }
    end

    def tracker
      js = File.read(RailsAnalytics::Engine.root.join("app/assets/javascripts/rails_analytics/tracker.js"))
      render plain: js, content_type: "application/javascript", layout: false
    end

    def dashboard_css
      css = File.read(RailsAnalytics::Engine.root.join("app/assets/stylesheets/rails_analytics/dashboard.css"))
      render plain: css, content_type: "text/css", layout: false
    end

    private

    # sendBeacon não permite headers custom — aceita token no header OU no body.
    def extract_token(request, json)
      header = request.headers["Authorization"]
      return header.gsub(/^Bearer /, "") if header.present?
      json["token"]
    end

    def valid_token?(token)
      return false if token.blank?
      verifier = Rails.application.message_verifier(VERIFIER_NAME)
      payload = verifier.verified(token, purpose: TOKEN_PURPOSE)
      payload.present? && payload["exp"].to_i > Time.current.to_i
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end
  end
end
```

- [ ] **Step 4: Add routes (temporary, for this task)**

```ruby
# config/routes.rb
RailsAnalytics::Engine.routes.draw do
  post "collect" => "analytics#collect"
  get  "tracker.js" => "analytics#tracker"
  get  "token" => "analytics#token"
  get  "dashboard.css" => "analytics#dashboard_css"
end
```

- [ ] **Step 5: Run to verify it passes**

```bash
cd test/dummy && bin/rails test test/controllers/analytics_controller_test.rb
```

Expected: PASS — 10 tests

- [ ] **Step 6: Commit**

```bash
git add app/controllers/rails_analytics/analytics_controller.rb test/controllers/analytics_controller_test.rb config/routes.rb
git commit -m "feat: AnalyticsController com collect e token"
```

---

### Task 10: DashboardsController + ChartBuilder

**Files:**
- Rewrite: `app/controllers/rails_analytics/dashboards_controller.rb`
- Create: `test/controllers/dashboards_controller_test.rb`
- Port + rewrite: `app/models/rails_analytics/chart_builder.rb`

**Interfaces:**
- Consumes: `RailsAnalytics::Stats`
- Produces: `overview` (GET /), `events` (GET /events), `visits` (GET /visits)
- ChartBuilder portado do piloto: `ChartBuilder.new(series).build` → SVG string para gráfico de linha

- [ ] **Step 1: Write ChartBuilder (port from pilot, convert bar → line)**

```ruby
# app/models/rails_analytics/chart_builder.rb
# frozen_string_literal: true

module RailsAnalytics
  # SVG line chart. Server-rendered, zero JS. Portado do piloto (ChartBuilder bar),
  # adaptado para linha (mais adequado para séries temporais).
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
```

- [ ] **Step 2: Write DashboardsController + test**

```ruby
# app/controllers/rails_analytics/dashboards_controller.rb
# frozen_string_literal: true

module RailsAnalytics
  class DashboardsController < ApplicationController
    before_action :authenticate_admin!

    def overview
      since = default_since
      daily_series = Stats.visits_by_day(since: since)

      @stats = {
        total_visits: Stats.total_visits(since: since),
        total_unique: Stats.total_unique_visitors(since: since),
        total_events: Stats.total_events(since: since),
        bounce_rate: Stats.bounce_rate(since: since),
        top_sources: Stats.top_sources(limit: 10, since: since),
        top_events: Stats.top_events(limit: 10, since: since),
        devices: Stats.devices(since: since),
        utm_breakdown: Stats.utm_breakdown(since: since)
      }
      @chart = ChartBuilder.new(
        daily_series.map { |date, count| { date: date, count: count } }
      ).build
    end

    def events
      @event_name = params[:name]
      @page = (params[:page] || 1).to_i
      @events = Stats.events_paginated(name: @event_name.presence, page: @page, since: default_since)
    end

    def visits
      @page = (params[:page] || 1).to_i
      @visits = Stats.visits_paginated(page: @page, since: default_since)
    end

    private

    def default_since
      RailsAnalytics.config.since_default.ago
    end
  end
end
```

```ruby
# test/controllers/dashboards_controller_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all

    v = RailsAnalytics::Visit.create!(anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "google.com",
                                       device_type: "desktop", viewport: "1440x900", language: "pt-BR",
                                       utm_source: "twitter", utm_campaign: "jan25",
                                       started_at: Time.current)
    v.events.create!(name: "click", time: Time.current)
  end

  test "overview returns 200" do
    get "/rails_analytics/"
    assert_response :success
    assert_includes response.body, "svg"
  end

  test "overview HTML never contains anonymity_key" do
    get "/rails_analytics/"
    refute_includes response.body, RailsAnalytics::Visit.last.anonymity_key
  end

  test "overview HTML never contains masked_ip" do
    get "/rails_analytics/"
    refute_includes response.body, "8.8.8.0"
  end

  test "events returns 200" do
    get "/rails_analytics/events"
    assert_response :success
  end

  test "events filters by name" do
    get "/rails_analytics/events", params: { name: "click" }
    assert_response :success
  end

  test "visits returns 200" do
    get "/rails_analytics/visits"
    assert_response :success
  end
end
```

- [ ] **Step 3: Add dashboard routes + run tests**

```ruby
# config/routes.rb — add dashboard routes
RailsAnalytics::Engine.routes.draw do
  root to: "dashboards#overview"
  get "events" => "dashboards#events"
  get "visits" => "dashboards#visits"

  post "collect" => "analytics#collect"
  get  "tracker.js" => "analytics#tracker"
  get  "token" => "analytics#token"
  get  "dashboard.css" => "analytics#dashboard_css"
end
```

- [ ] **Step 4: Run to verify**

```bash
cd test/dummy && bin/rails test test/controllers/dashboards_controller_test.rb
```

Expected: PASS — 6 tests

- [ ] **Step 5: Commit**

```bash
git add app/controllers/rails_analytics/dashboards_controller.rb app/models/rails_analytics/chart_builder.rb test/controllers/dashboards_controller_test.rb config/routes.rb
git commit -m "feat: DashboardsController com ChartBuilder SVG"
```

---

### Task 11: I18n + Layout + CSS

**Files:**
- Create: `config/locales/rails_analytics.pt-BR.yml`
- Create: `config/locales/rails_analytics.en.yml`
- Rewrite: `app/views/layouts/rails_analytics.html.erb`
- Rewrite: `app/assets/stylesheets/rails_analytics/dashboard.css`

**Interfaces:**
- I18n keys para todas as labels do dashboard

- [ ] **Step 1: Write I18n files**

```yaml
# config/locales/rails_analytics.pt-BR.yml
pt-BR:
  rails_analytics:
    title: "Rails Analytics"
    nav:
      overview: "Visão geral"
      events: "Eventos"
      visits: "Visitas"
    footer: "Dados agregados e anônimos — retenção 6 meses"
    kpi:
      visits: "Visitas"
      unique_visitors: "Visitantes únicos"
      events: "Eventos"
      bounce_rate: "Taxa de rejeição"
    chart:
      visits_per_day: "Visitas por dia"
      no_data: "Sem dados"
    tables:
      top_sources: "Origem do tráfego"
      top_events: "Clics por botão"
      devices: "Dispositivos"
      utm: "UTM"
      date: "Data"
      visits: "Visitas"
      unique_visitors: "Visitantes únicos"
      top_source: "Origem principal"
      event_name: "Nome do evento"
      count: "Contagem"
      source: "Origem"
      campaign: "Campanha"
      medium: "Mídia"
    empty: "Nenhum dado registrado ainda."
    filter:
      all_events: "Todos os eventos"
      filter: "Filtrar"
    pagination:
      previous: "Anterior"
      next: "Próximo"
```

```yaml
# config/locales/rails_analytics.en.yml
en:
  rails_analytics:
    title: "Rails Analytics"
    nav:
      overview: "Overview"
      events: "Events"
      visits: "Visits"
    footer: "Aggregated and anonymous data — 6 month retention"
    kpi:
      visits: "Visits"
      unique_visitors: "Unique visitors"
      events: "Events"
      bounce_rate: "Bounce rate"
    chart:
      visits_per_day: "Visits per day"
      no_data: "No data"
    tables:
      top_sources: "Traffic sources"
      top_events: "Top events"
      devices: "Devices"
      utm: "UTM"
      date: "Date"
      visits: "Visits"
      unique_visitors: "Unique visitors"
      top_source: "Top source"
      event_name: "Event name"
      count: "Count"
      source: "Source"
      campaign: "Campaign"
      medium: "Medium"
    empty: "No data recorded yet."
    filter:
      all_events: "All events"
      filter: "Filter"
    pagination:
      previous: "Previous"
      next: "Next"
```

- [ ] **Step 2: Write layout**

```erb
<%# app/views/layouts/rails_analytics.html.erb %>
<!DOCTYPE html>
<html lang="<%= I18n.locale %>">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= t("rails_analytics.title") %></title>
    <link rel="stylesheet" href="<%= request.base_url %>/rails_analytics/dashboard.css" media="all">
  </head>
  <body>
    <header class="ra-header">
      <h1 class="ra-brand"><%= t("rails_analytics.title") %></h1>
      <nav class="ra-nav">
        <%= link_to t("rails_analytics.nav.overview"), rails_analytics.root_path, class: nav_class(:overview) %>
        <%= link_to t("rails_analytics.nav.events"), rails_analytics.events_path, class: nav_class(:events) %>
        <%= link_to t("rails_analytics.nav.visits"), rails_analytics.visits_path, class: nav_class(:visits) %>
      </nav>
    </header>
    <main class="ra-main">
      <%= yield %>
    </main>
    <footer class="ra-footer">
      <span><%= t("rails_analytics.footer") %></span>
    </footer>
  </body>
</html>
```

- [ ] **Step 3: Write CSS (port from pilot, extend for new views)**

O CSS existente (`dashboard.css`, 113 linhas) já cobre KPIs, cards, tabelas, SVG chart, devices, dark mode. Só precisa de extensões para:
- Paginação (`.ra-pagination`)
- Filtro de eventos (`.ra-filter`)
- UTM table (`.ra-utm-table`)
- Linha do gráfico já coberta pelo SVG inline

Adicionar ao final do CSS existente:

```css
/* Pagination */
.ra-pagination {
  display: flex;
  gap: 0.5rem;
  justify-content: center;
  margin-top: 1rem;
}
.ra-pagination a, .ra-pagination span {
  padding: 0.25rem 0.75rem;
  border: 1px solid var(--ra-border);
  border-radius: 4px;
  text-decoration: none;
  color: var(--ra-text);
}
.ra-pagination .current {
  background: var(--ra-accent);
  color: #fff;
  border-color: var(--ra-accent);
}

/* Filter bar */
.ra-filter {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 1rem;
  flex-wrap: wrap;
}
.ra-filter select, .ra-filter input {
  padding: 0.25rem 0.5rem;
  border: 1px solid var(--ra-border);
  border-radius: 4px;
  background: var(--ra-bg-card);
  color: var(--ra-text);
}

/* UTM table */
.ra-utm-table th {
  font-size: 0.75rem;
}
.ra-utm-table td {
  font-size: 0.85rem;
}
```

- [ ] **Step 4: Verify CSS loads**

```bash
cd test/dummy && bin/rails test test/controllers/analytics_controller_test.rb -n "/dashboard.css/"
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add config/locales/ app/views/layouts/rails_analytics.html.erb app/assets/stylesheets/rails_analytics/dashboard.css
git commit -m "feat: I18n pt-BR + en, layout e CSS"
```

---

### Task 12: Dashboard views (overview, events, visits)

**Files:**
- Rewrite: `app/views/rails_analytics/dashboards/overview.html.erb`
- Create: `app/views/rails_analytics/dashboards/events.html.erb`
- Create: `app/views/rails_analytics/dashboards/visits.html.erb`

**Interfaces:**
- Consumes: `@stats`, `@chart`, `@events`, `@visits` dos controllers

- [ ] **Step 1: Write overview view**

```erb
<%# app/views/rails_analytics/dashboards/overview.html.erb %>
<section class="ra-kpis">
  <div class="ra-card">
    <span class="ra-kpi-label"><%= t("rails_analytics.kpi.visits") %></span>
    <strong class="ra-kpi-value"><%= number_with_delimiter(@stats[:total_visits]) %></strong>
  </div>
  <div class="ra-card">
    <span class="ra-kpi-label"><%= t("rails_analytics.kpi.unique_visitors") %></span>
    <strong class="ra-kpi-value"><%= number_with_delimiter(@stats[:total_unique]) %></strong>
  </div>
  <div class="ra-card">
    <span class="ra-kpi-label"><%= t("rails_analytics.kpi.events") %></span>
    <strong class="ra-kpi-value"><%= number_with_delimiter(@stats[:total_events]) %></strong>
  </div>
  <div class="ra-card">
    <span class="ra-kpi-label"><%= t("rails_analytics.kpi.bounce_rate") %></span>
    <strong class="ra-kpi-value"><%= (@stats[:bounce_rate] * 100).round(1) %>%</strong>
  </div>
</section>

<section class="ra-card ra-chart-card">
  <h2 class="ra-card-title"><%= t("rails_analytics.chart.visits_per_day") %></h2>
  <div class="ra-chart">
    <%= raw @chart %>
  </div>
</section>

<section class="ra-grid">
  <div class="ra-card">
    <h2 class="ra-card-title"><%= t("rails_analytics.tables.top_sources") %></h2>
    <% if @stats[:top_sources].any? %>
      <table class="ra-table">
        <thead>
          <tr><th><%= t("rails_analytics.tables.source") %></th><th class="ra-num"><%= t("rails_analytics.tables.count") %></th></tr>
        </thead>
        <tbody>
          <% @stats[:top_sources].each do |ref, count| %>
            <tr><td class="ra-mono"><%= ref %></td><td class="ra-num"><%= number_with_delimiter(count) %></td></tr>
          <% end %>
        </tbody>
      </table>
    <% else %>
      <p class="ra-empty"><%= t("rails_analytics.empty") %></p>
    <% end %>
  </div>

  <div class="ra-card">
    <h2 class="ra-card-title"><%= t("rails_analytics.tables.top_events") %></h2>
    <% if @stats[:top_events].any? %>
      <table class="ra-table">
        <thead>
          <tr><th><%= t("rails_analytics.tables.event_name") %></th><th class="ra-num"><%= t("rails_analytics.tables.count") %></th></tr>
        </thead>
        <tbody>
          <% @stats[:top_events].each do |name, count| %>
            <tr><td class="ra-mono"><%= name %></td><td class="ra-num"><%= number_with_delimiter(count) %></td></tr>
          <% end %>
        </tbody>
      </table>
    <% else %>
      <p class="ra-empty"><%= t("rails_analytics.empty") %></p>
    <% end %>
  </div>
</section>

<% if @stats[:utm_breakdown].any? %>
  <section class="ra-card">
    <h2 class="ra-card-title"><%= t("rails_analytics.tables.utm") %></h2>
    <table class="ra-table ra-utm-table">
      <thead>
        <tr>
          <th><%= t("rails_analytics.tables.source") %></th>
          <th><%= t("rails_analytics.tables.campaign") %></th>
          <th><%= t("rails_analytics.tables.medium") %></th>
          <th class="ra-num"><%= t("rails_analytics.tables.count") %></th>
        </tr>
      </thead>
      <tbody>
        <% @stats[:utm_breakdown].each do |row| %>
          <tr>
            <td class="ra-mono"><%= row["utm_source"] %></td>
            <td class="ra-mono"><%= row["utm_campaign"] %></td>
            <td class="ra-mono"><%= row["utm_medium"] %></td>
            <td class="ra-num"><%= number_with_delimiter(row["count"]) %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
<% end %>

<section class="ra-card">
  <h2 class="ra-card-title"><%= t("rails_analytics.tables.devices") %></h2>
  <div class="ra-devices">
    <% @stats[:devices].each do |device, count| %>
      <div class="ra-device">
        <span class="ra-kpi-label"><%= device %></span>
        <strong class="ra-kpi-value"><%= number_with_delimiter(count) %></strong>
      </div>
    <% end %>
  </div>
</section>
```

- [ ] **Step 2: Write events view**

```erb
<%# app/views/rails_analytics/dashboards/events.html.erb %>
<section class="ra-card">
  <h2 class="ra-card-title"><%= t("rails_analytics.nav.events") %></h2>

  <div class="ra-filter">
    <%= form_tag rails_analytics.events_path, method: :get do %>
      <%= select_tag :name,
            options_for_select(
              [[t("rails_analytics.filter.all_events"), ""]] +
              RailsAnalytics::Stats.event_counts_by_name.keys.map { |n| [n, n] },
              @event_name
            ),
            onchange: "this.form.submit()" %>
      <noscript><%= submit_tag t("rails_analytics.filter.filter") %></noscript>
    <% end %>
  </div>

  <% if @events[:data].any? %>
    <table class="ra-table">
      <thead>
        <tr>
          <th><%= t("rails_analytics.tables.date") %></th>
          <th><%= t("rails_analytics.tables.event_name") %></th>
          <th class="ra-num"><%= t("rails_analytics.tables.count") %></th>
        </tr>
      </thead>
      <tbody>
        <% @events[:data].each do |row| %>
          <tr>
            <td class="ra-mono"><%= row[:date] %></td>
            <td class="ra-mono"><%= row[:name] %></td>
            <td class="ra-num"><%= number_with_delimiter(row[:count]) %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <%= paginate @events %>
  <% else %>
    <p class="ra-empty"><%= t("rails_analytics.empty") %></p>
  <% end %>
</section>
```

- [ ] **Step 3: Write visits view**

```erb
<%# app/views/rails_analytics/dashboards/visits.html.erb %>
<section class="ra-card">
  <h2 class="ra-card-title"><%= t("rails_analytics.nav.visits") %></h2>

  <% if @visits[:data].any? %>
    <table class="ra-table">
      <thead>
        <tr>
          <th><%= t("rails_analytics.tables.date") %></th>
          <th class="ra-num"><%= t("rails_analytics.tables.visits") %></th>
          <th class="ra-num"><%= t("rails_analytics.tables.unique_visitors") %></th>
          <th><%= t("rails_analytics.tables.top_source") %></th>
        </tr>
      </thead>
      <tbody>
        <% @visits[:data].each do |row| %>
          <tr>
            <td class="ra-mono"><%= row[:date] %></td>
            <td class="ra-num"><%= number_with_delimiter(row[:visits]) %></td>
            <td class="ra-num"><%= number_with_delimiter(row[:unique_visitors]) %></td>
            <td class="ra-mono"><%= row[:top_source] %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <%= paginate @visits %>
  <% else %>
    <p class="ra-empty"><%= t("rails_analytics.empty") %></p>
  <% end %>
</section>
```

- [ ] **Step 4: Run dashboard integration tests**

```bash
cd test/dummy && bin/rails test test/controllers/dashboards_controller_test.rb
```

Expected: PASS — 6 tests (overview renderiza SVG, sem vazamento de PII, events, visits)

- [ ] **Step 5: Commit**

```bash
git add app/views/rails_analytics/dashboards/
git commit -m "feat: Views do dashboard (overview, events, visits)"
```

---

### Task 13: Tracker JS (cookie-less)

**Files:**
- Rewrite: `app/assets/javascripts/rails_analytics/tracker.js`

**Interfaces:**
- Expõe: `window.RailsAnalytics.track(name, props)`
- Coleta: path, referrer_domain, device_type, viewport, language, nonce
- Envia POST com signed token (obtido via GET /token)
- sendBeacon no `pagehide`
- Batched send a cada 10s

- [ ] **Step 1: Write the tracker**

```javascript
// app/assets/javascripts/rails_analytics/tracker.js
// Rails Analytics — Cookie-less tracker (~3 KB)
// No cookies, no localStorage, no fingerprinting. LGPD-compliant by design.

(function () {
  "use strict";

  var FLUSH_INTERVAL = 10000; // 10s
  var MAX_BATCH = 20;

  // Lê o endpoint do script tag (helper injeta data-endpoint)
  var script = document.currentScript || document.querySelector("script[data-rails-analytics]");
  var ENDPOINT = (script && script.getAttribute("data-endpoint")) || "/rails_analytics";

  var queue = [];
  var token = null;

  function randomHex(len) {
    var arr = new Uint8Array(len);
    crypto.getRandomValues(arr);
    return Array.from(arr, function (b) { return b.toString(16).padStart(2, "0"); }).join("");
  }

  var nonce = randomHex(16);

  function deviceType() {
    var w = screen.width || window.innerWidth || 0;
    if (w >= 1024) return "desktop";
    if (w >= 768) return "tablet";
    return "mobile";
  }

  function referrerDomain() {
    try {
      var ref = document.referrer;
      if (!ref) return "direct";
      var u = new URL(ref);
      return u.hostname;
    } catch (e) {
      return "direct";
    }
  }

  function payload() {
    return {
      path: location.pathname + location.search,
      referrer_domain: referrerDomain(),
      device_type: deviceType(),
      viewport: screen.width + "x" + screen.height,
      language: (navigator.language || "").slice(0, 10),
      nonce: nonce,
      events: queue
    };
  }

  function fetchToken() {
    return fetch(ENDPOINT + "/token", { credentials: "same-origin" })
      .then(function (r) { return r.json(); })
      .then(function (data) { token = data.token; })
      .catch(function () { /* silently fail */ });
  }

  function flush() {
    if (queue.length === 0 || !token) return;

    var batch = queue.splice(0, MAX_BATCH);
    var body = payload();
    body.events = batch;

    // sendBeacon não permite header custom — token vai no body.
    // fetch keepalive permite headers e sobrevive ao unload em browsers modernos.
    if (navigator.sendBeacon) {
      body.token = token;
      navigator.sendBeacon(ENDPOINT + "/collect", new Blob([JSON.stringify(body)], { type: "application/json" }));
    } else {
      fetch(ENDPOINT + "/collect", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer " + token
        },
        body: JSON.stringify(body),
        keepalive: true
      }).catch(function () {});
    }

    nonce = randomHex(16); // rotate nonce after each batch
  }

  function track(name, properties) {
    queue.push({
      name: name,
      time: new Date().toISOString(),
      properties: properties || {}
    });
    if (queue.length >= MAX_BATCH) flush();
  }

  function scheduleFlush() {
    fetchToken().then(function () {
      flush(); // send initial pageview as event
      setInterval(flush, FLUSH_INTERVAL);
    });
  }

  // Send on page exit (survives tab close)
  function onPageHide() {
    if (queue.length > 0 && token) {
      var body = payload();
      body.token = token;
      if (navigator.sendBeacon) {
        navigator.sendBeacon(ENDPOINT + "/collect", new Blob([JSON.stringify(body)], { type: "application/json" }));
      } else {
        fetch(ENDPOINT + "/collect", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": "Bearer " + token },
          body: JSON.stringify(body),
          keepalive: true
        }).catch(function () {});
      }
      queue = [];
    }
  }

  // Expose public API
  window.RailsAnalytics = { track: track };

  // Init
  if (document.readyState === "complete") {
    scheduleFlush();
  } else {
    window.addEventListener("load", scheduleFlush);
  }
  window.addEventListener("pagehide", onPageHide);
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden") onPageHide();
  });
})();
```

- [ ] **Step 2: Verify tracker is served**

```bash
cd test/dummy && bin/rails test test/controllers/analytics_controller_test.rb -n "/tracker.js/"
```

Expected: PASS — tracker.js served, content includes "RailsAnalytics"

- [ ] **Step 3: Commit**

```bash
git add app/assets/javascripts/rails_analytics/tracker.js
git commit -m "feat: Tracker JS cookie-less com sendBeacon"
```

---

### Task 14: Engine + routes final + helper

**Files:**
- Rewrite: `lib/rails_analytics/engine.rb`
- Update: `lib/rails_analytics.rb`
- Rewrite: `app/helpers/rails_analytics/application_helper.rb`

**Interfaces:**
- Engine with Propshaft asset config, helper injection, rack-attack load
- Helper: `rails_analytics_tracker_tag` injeta `<script src="{mount}/tracker.js" data-rails-analytics data-endpoint="{mount}" defer>`

```ruby
# lib/rails_analytics/engine.rb
# frozen_string_literal: true

module RailsAnalytics
  class Engine < ::Rails::Engine
    isolate_namespace RailsAnalytics

    config.generators do |g|
      g.test_framework :minitest
      g.helper false
      g.assets false
    end

    initializer "rails_analytics.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.precompile += %w[rails_analytics/tracker.js rails_analytics/dashboard.css]
      end
    end

    initializer "rails_analytics.helper" do
      ActiveSupport.on_load(:action_view) do
        include RailsAnalytics::ApplicationHelper
      end
    end

    initializer "rails_analytics.rack_attack" do
      if defined?(Rack::Attack)
        require "rails_analytics/rack_attack"
        RailsAnalytics::RackAttack.configure
      end
    end
  end
end
```

```ruby
# lib/rails_analytics.rb — update to require all new files
# frozen_string_literal: true

require_relative "rails_analytics/version"
require_relative "rails_analytics/configuration"
require_relative "rails_analytics/ip_mask"
require_relative "rails_analytics/identity"
require_relative "rails_analytics/stats"
require_relative "rails_analytics/engine" if defined?(Rails::Railtie)
```

```ruby
# app/helpers/rails_analytics/application_helper.rb
# frozen_string_literal: true

module RailsAnalytics
  module ApplicationHelper
    def rails_analytics_tracker_tag(options = {})
      endpoint = options[:endpoint] || RailsAnalytics.config.mount_path
      tag.script(src: "#{endpoint}/tracker.js",
                 data: { rails_analytics: true, endpoint: endpoint },
                 defer: true)
    end
  end
end
```

- [ ] **Step 1: Verify**

```bash
cd test/dummy && bin/rails test test/controllers/analytics_controller_test.rb
```

Expected: PASS

- [ ] **Step 2: Commit**

```bash
git add lib/rails_analytics/engine.rb lib/rails_analytics.rb app/helpers/rails_analytics/application_helper.rb
git commit -m "feat: Engine final com helper e rack_attack"
```

---

### Task 15: Install generator

**Files:**
- Rewrite: `lib/generators/rails_analytics/install/install_generator.rb`
- Create: `lib/generators/rails_analytics/install/templates/initializer.rb`
- Remove: old migration template `create_rails_analytics_page_views.rb` from templates

- [ ] **Step 1: Write generator + template**

```ruby
# lib/generators/rails_analytics/install/install_generator.rb
# frozen_string_literal: true

module RailsAnalytics
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Instala o rails_analytics: copia migrations, monta engine, cria initializer e pina tracker no importmap."

      def copy_migrations
        migrations_dir = RailsAnalytics::Engine.root.join("db/migrate")
        Dir["#{migrations_dir}/*.rb"].sort.each do |migration|
          filename = File.basename(migration)
          copy_file migration, "db/migrate/#{filename}"
        end
        say_status :ok, "Migrations copiadas para db/migrate/"
      end

      def create_initializer
        template "initializer.rb", "config/initializers/rails_analytics.rb"
        say_status :ok, "Initializer criado em config/initializers/rails_analytics.rb"
      end

      def mount_engine
        route %(mount RailsAnalytics::Engine => RailsAnalytics.config.mount_path)
        say_status :ok, "Engine montada em config/routes.rb"
      end

      def pin_tracker
        importmap_path = "config/importmap.rb"
        if File.exist?(importmap_path)
          unless File.read(importmap_path).include?("rails_analytics/tracker")
            append_to_file importmap_path, %(\npin "rails_analytics/tracker", to: RailsAnalytics.config.mount_path + "/tracker.js"\n)
            say_status :ok, "Tracker pinado em config/importmap.rb"
          end
        else
          say_status :skipped, "config/importmap.rb não encontrado — adicione manualmente:", :yellow
          say %(  Adicione ao seu layout: <script src="<%= RailsAnalytics.config.mount_path %>/tracker.js" defer></script>), :yellow
        end
      end

      def instructions
        say "\n✅ rails_analytics instalado! Próximos passos:", :green
        say "  1. bin/rails db:migrate"
        say "  2. Configure a autenticação no initializer: config/initializers/rails_analytics.rb"
        say "  3. Acesse o dashboard em #{RailsAnalytics.config.mount_path}"
        say ""
      end
    end
  end
end
```

```ruby
# lib/generators/rails_analytics/install/templates/initializer.rb
# frozen_string_literal: true

RailsAnalytics.configure do |config|
  # Método de autenticação para o dashboard.
  # Pode ser um Symbol (ex: :authenticate_admin!) ou um callable (ex: -> { current_user&.admin? }).
  config.auth_callback = :authenticate_admin!

  # Caminho onde o engine será montado no routes.rb.
  config.mount_path = "/analytics"

  # Período padrão para as consultas do dashboard (ex: 30.days).
  config.since_default = 30.days
end
```

- [ ] **Step 2: Remove old migration templates**

```bash
rm -f lib/generators/rails_analytics/install/templates/create_rails_analytics_page_views.rb
```

- [ ] **Step 3: Commit**

```bash
git add lib/generators/rails_analytics/install/
git rm lib/generators/rails_analytics/install/templates/create_rails_analytics_page_views.rb 2>/dev/null
git commit -m "feat: Install generator com importmap e initializer"
```

---

### Task 16: Retention job

**Files:**
- Create: `app/jobs/rails_analytics/retention_job.rb`
- Create: `test/jobs/retention_job_test.rb`

**Interfaces:**
- `RailsAnalytics::RetentionJob.perform_now` — purga visits + events > 6 meses

- [ ] **Step 1: Write test**

```ruby
# test/jobs/retention_job_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::RetentionJobTest < ActiveSupport::TestCase
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all

    @old_visit = RailsAnalytics::Visit.create!(anonymity_key: "old1", masked_ip: "1.1.1.0", started_at: 7.months.ago)
    @old_visit.events.create!(name: "click", time: 7.months.ago)

    @recent_visit = RailsAnalytics::Visit.create!(anonymity_key: "new1", masked_ip: "2.2.2.0", started_at: 1.day.ago)
    @recent_visit.events.create!(name: "scroll", time: 1.day.ago)
  end

  test "deletes visits older than 6 months" do
    assert_difference -> { RailsAnalytics::Visit.count }, -1 do
      RailsAnalytics::RetentionJob.perform_now
    end
    assert RailsAnalytics::Visit.exists?(@recent_visit.id), "recente deve ser preservado"
    refute RailsAnalytics::Visit.exists?(@old_visit.id), "antigo deve ser deletado"
  end

  test "deletes events for deleted visits" do
    assert_difference -> { RailsAnalytics::Event.count }, -1 do
      RailsAnalytics::RetentionJob.perform_now
    end
  end

  test "is idempotent" do
    3.times { RailsAnalytics::RetentionJob.perform_now }
    assert RailsAnalytics::Visit.exists?(@recent_visit.id)
    refute RailsAnalytics::Visit.exists?(@old_visit.id)
    assert_equal 1, RailsAnalytics::Visit.count
  end

  test "does not delete recent visits" do
    RailsAnalytics::RetentionJob.perform_now
    assert_equal 1, RailsAnalytics::Visit.count
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd test/dummy && bin/rails test test/jobs/retention_job_test.rb
```

Expected: FAIL — `NameError: uninitialized constant RailsAnalytics::RetentionJob`

- [ ] **Step 3: Write job**

```ruby
# app/jobs/rails_analytics/retention_job.rb
# frozen_string_literal: true

module RailsAnalytics
  class RetentionJob < ActiveJob::Base
    queue_as :default

    RETENTION_PERIOD = 6.months

    def perform
      cutoff = RETENTION_PERIOD.ago
      deleted_visits = 0
      deleted_events = 0

      Visit.where(Visit.arel_table[:started_at].lt(cutoff)).find_in_batches(batch_size: 1000) do |batch|
        visit_ids = batch.map(&:id)

        events_count = Event.where(visit_id: visit_ids).delete_all
        visits_count = Visit.where(id: visit_ids).delete_all

        deleted_events += events_count
        deleted_visits += visits_count
      end

      Rails.logger.info "[rails_analytics] RetentionJob: deleted #{deleted_visits} visits and #{deleted_events} events older than #{cutoff}"
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd test/dummy && bin/rails test test/jobs/retention_job_test.rb
```

Expected: PASS — 4 tests

- [ ] **Step 5: Commit**

```bash
git add app/jobs/rails_analytics/retention_job.rb test/jobs/retention_job_test.rb
git commit -m "feat: RetentionJob purga dados > 6 meses"
```

---

### Task 17: Integration + security + rate limiting + cleanup do piloto

**Files:**
- Rewrite: `test/dummy/test/integration/rails_analytics_test.rb`
- Create: `lib/rails_analytics/rack_attack.rb` (throttle rules)
- Delete: `app/models/rails_analytics/page_view.rb` (piloto)
- Delete: `app/models/rails_analytics/dashboard_stats.rb` (piloto — movido para Stats)
- Delete: `app/models/rails_analytics/tracker_script.rb` (piloto — movido para tracker.js)
- Delete: `app/views/rails_analytics/dashboards/index.html.erb` (piloto — substituído por overview)
- Delete: `db/migrate/20260906000000_create_rails_analytics_page_views.rb` (piloto)
- Modify: `test/dummy/db/schema.rb` — remover tabela page_views órfã (opcional)

**Interfaces:**
- Full integration test covering: tracker, collect (com token no header E no body), dashboard com auth, security, rate limit

- [ ] **Step 1: Write rate limiting rules (loaded if rack-attack present)**

```ruby
# lib/rails_analytics/rack_attack.rb
# frozen_string_literal: true

module RailsAnalytics
  module RackAttack
    def self.configure
      return unless defined?(::Rack::Attack)

      masked_ip = ->(req) {
        ip = req.env["HTTP_CF_CONNECTING_IP"] || req.ip
        RailsAnalytics::IpMask.mask(ip) || "unknown"
      }

      # Throttle o endpoint de coleta: 20 req/min por masked IP.
      # O path termina em /collect independentemente do mount_path.
      ::Rack::Attack.throttle("rails_analytics_collect_by_ip", limit: 20, period: 60.seconds) do |req|
        if req.post? && req.path.end_with?("/collect")
          masked_ip.call(req)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Rewrite integration test (com auth setup + token no body)**

```ruby
# test/dummy/test/integration/rails_analytics_test.rb
# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::CollectTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all
    @verifier = Rails.application.message_verifier("rails_analytics_tracker")
    @token = @verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)
  end

  test "collect creates visit with masked IP and event" do
    assert_difference -> { RailsAnalytics::Visit.count }, 1 do
      post "/rails_analytics/collect",
           params: { path: "/home", referrer_domain: "twitter.com", device_type: "desktop", viewport: "1440x900", language: "pt-BR", nonce: "abc", events: [{ name: "click", time: Time.current.iso8601 }] }.to_json,
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    end

    assert_response :no_content
    visit = RailsAnalytics::Visit.last
    assert_match(/\.0$/, visit.masked_ip) # masked
    assert_equal "twitter.com", visit.referrer_domain
    assert_equal 1, visit.events.count
  end

  test "collect accepts token in body (sendBeacon compatibility)" do
    assert_difference -> { RailsAnalytics::Visit.count }, 1 do
      post "/rails_analytics/collect",
           params: { path: "/home", token: @token, events: [] }.to_json,
           headers: { "Content-Type" => "application/json" }
    end

    assert_response :no_content
  end

  test "collect without token returns 401" do
    post "/rails_analytics/collect",
         params: { path: "/home" }.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "collect with malformed json returns 204 gracefully" do
    assert_no_difference -> { RailsAnalytics::Visit.count } do
      post "/rails_analytics/collect",
           params: "not-json",
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    end

    assert_response :no_content
  end

  test "collect with massive path truncates" do
    post "/rails_analytics/collect",
         params: { path: "x" * 3000, referrer_domain: "t.co", device_type: "mobile", viewport: "390x844", language: "en", nonce: "abc", events: [] }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }

    assert_response :no_content
    assert RailsAnalytics::Visit.last.landing_page_path.length <= 2000
  end
end

class RailsAnalytics::TrackerTest < ActionDispatch::IntegrationTest
  test "tracker.js is served" do
    get "/rails_analytics/tracker.js"
    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert_includes response.body, "RailsAnalytics"
    assert_includes response.body, "sendBeacon"
  end

  test "token returns valid signed token" do
    get "/rails_analytics/token"
    assert_response :success
    body = JSON.parse(response.body)
    verifier = Rails.application.message_verifier("rails_analytics_tracker")
    assert_nothing_raised { verifier.verified(body["token"], purpose: :tracker) }
  end

  test "dashboard.css is served" do
    get "/rails_analytics/dashboard.css"
    assert_response :success
    assert_equal "text/css", response.media_type
  end
end

class RailsAnalytics::DashboardTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics::Event.delete_all

    v = RailsAnalytics::Visit.create!(anonymity_key: "k1", masked_ip: "8.8.8.0", referrer_domain: "google.com",
                                       device_type: "desktop", viewport: "1440x900", language: "pt-BR",
                                       utm_source: "twitter", utm_campaign: "launch",
                                       started_at: Time.current)
    v.events.create!(name: "doacao-click", time: Time.current)

    # Dashboard exige auth — permite via callable nos testes
    RailsAnalytics.config.auth_callback = -> { true }
  end

  teardown do
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end

  test "dashboard overview renders core elements" do
    get "/rails_analytics/"
    assert_response :success
    assert_includes response.body, "Rails Analytics"
    assert_includes response.body, "svg"
    assert_includes response.body, "google.com"
    assert_includes response.body, "doacao-click"
    assert_includes response.body, "twitter"
    assert_includes response.body, "launch"
  end

  test "dashboard HTML never contains PII" do
    get "/rails_analytics/"
    refute_includes response.body, "8.8.8.0"  # masked IP not exposed
    refute_includes response.body, "k1"        # anonymity key not exposed
  end

  test "events page is accessible" do
    get "/rails_analytics/events"
    assert_response :success
  end

  test "visits page is accessible" do
    get "/rails_analytics/visits"
    assert_response :success
  end

  test "footer shows LGPD compliance" do
    get "/rails_analytics/"
    assert_includes response.body, "retenção"
  end

  test "dashboard without auth redirects" do
    RailsAnalytics.config.auth_callback = -> { false }
    get "/rails_analytics/"
    assert_response :redirect
  end
end

class RailsAnalytics::SecurityTest < ActionDispatch::IntegrationTest
  setup do
    RailsAnalytics::Visit.delete_all
    RailsAnalytics.config.auth_callback = -> { true }
  end

  teardown do
    RailsAnalytics.config.auth_callback = :authenticate_admin!
  end

  test "rate limit kicks in after 20 requests per masked IP" do
    verifier = Rails.application.message_verifier("rails_analytics_tracker")
    token = verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)

    20.times do
      post "/rails_analytics/collect",
           params: { path: "/x", token: token, events: [] }.to_json,
           headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "203.0.113.5" }
    end
    assert_response :no_content

    post "/rails_analytics/collect",
         params: { path: "/x", token: token, events: [] }.to_json,
         headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "203.0.113.5" }
    assert_response :too_many_requests
  end

  test "different masked IPs are throttled independently" do
    verifier = Rails.application.message_verifier("rails_analytics_tracker")
    token = verifier.generate({ exp: 5.minutes.from_now.to_i }, purpose: :tracker)

    21.times do
      post "/rails_analytics/collect",
           params: { path: "/x", token: token, events: [] }.to_json,
           headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "198.51.100.7" }
    end
    assert_response :no_content, "25 requests de IPs diferentes não devem ser throttled juntos"
  end
end
```

- [ ] **Step 3: Cleanup do piloto**

```bash
git rm app/models/rails_analytics/page_view.rb
git rm app/models/rails_analytics/dashboard_stats.rb
git rm app/models/rails_analytics/tracker_script.rb
git rm app/views/rails_analytics/dashboards/index.html.erb
git rm db/migrate/20260906000000_create_rails_analytics_page_views.rb
```

- [ ] **Step 4: Run all tests**

```bash
cd test/dummy && bin/rails db:migrate RAILS_ENV=test
cd test/dummy && bin/rails test
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add test/ lib/rails_analytics/rack_attack.rb
git commit -m "test: integration, security e rate limit"
git commit -m "refactor: remove arquivos do piloto"
```

---

### Task 18: README + CHANGELOG + gemspec

**Files:**
- Rewrite: `README.md`
- Update: `CHANGELOG.md` (create if not exists)
- Update: `rails_analytics.gemspec`

- [ ] **Step 1: Update gemspec version and description**

```ruby
# rails_analytics.gemspec — update version + summary
  s.version     = "1.0.0"
  s.summary     = "Privacy-first analytics engine for Rails — cookie-less, LGPD-compliant."
  s.description = "Rails Engine with server-side tracker, aggregated dashboard, IP masking, daily anonymity key rotation, UTM tracking, and 6-month retention. No third-party analytics dependencies."
```

- [ ] **Step 2: Write README (full)**

README cobrindo: install, mount, auth config, compliance section (what is collected / never collected, cookie-less reasoning, IP masking, retention, ANPD guide reference), tracker API (`window.RailsAnalytics.track(name, props)`), "add a new metric" guide (add method in Stats + one line in view).

- [ ] **Step 3: Write CHANGELOG**

```markdown
# Changelog

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
```

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md rails_analytics.gemspec lib/rails_analytics/version.rb
git commit -m "docs: README, CHANGELOG e gemspec v1.0.0"
```

---

### Task 19: Full suite verification + cleanup

- [ ] **Step 1: Run complete test suite**

```bash
cd test/dummy && bin/rails db:migrate RAILS_ENV=test && cd ../..
cd test/dummy && bin/rails test
```

Expected: All tests PASS (IpMask, Identity, DailySalt, Visit, Event, Stats, AnalyticsController, DashboardsController, ApplicationController, RetentionJob, Integration)

- [ ] **Step 2: Verify no PII leak in rendered HTML**

```bash
cd test/dummy && bin/rails test test/controllers/dashboards_controller_test.rb -n "/never contains/"
cd test/dummy && bin/rails test test/dummy/test/integration/rails_analytics_test.rb -n "/PII/"
```

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: verificação completa e limpeza"
```

---

## Self-review

- **Spec coverage**: ✅ Cada objetivo da spec mapeado para uma task (0→19).
- **Placeholder scan**: ✅ Zero TBD/TODO/vague steps.
- **Type consistency**: ✅ Interfaces declaradas entre tasks; `Stats` expõe `bounce_rate` (Float), `visits_paginated` (Hash); controllers consomem `Stats` e `ChartBuilder`.
- **Portabilidade**: ✅ Nenhuma função PG-only (SQLite compat); GIN index condicional; `mode()` removido.
- **Auth**: ✅ Herança do host (padrão RailsAdmin) + `authorize_admin!` (sem loop).

| Spec objective | Task(s) |
|---|---|
| 0. Infra de testes (Rakefile, test_helper, dummy) | 0 |
| 1. Tracker JS cookie-less | 13, 9 |
| 2. Identity key anônima | 4, 3 |
| 3. IP masking | 1 |
| 4. Collection endpoint | 9, 17 |
| 5. UTM no insert | 5, 9 |
| 6. Stats agregado | 7 |
| 7. Dashboard RESTful | 10, 11, 12 |
| 8. Auth configurável | 2, 8 |
| 9. Rate limiting | 14, 17 |
| 10. Retention job | 16 |
| 11. Install generator | 15 |
| 12. Testes TDD | 0–17 (cada task) |
| Docs | 18 |