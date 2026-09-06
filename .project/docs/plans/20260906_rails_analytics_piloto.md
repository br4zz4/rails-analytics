---
title: Rails Analytics — Piloto (coleta de tráfego + dashboard)
spec: null
created: 2026-09-06
updated: 2026-09-06
certainty: high
---

# Rails Analytics — Plano de implementação (piloto)

> **TLDR**: gem Rails estilo Umami que coleta tráfego via pixel + tracker JS, salva no banco da host app através de uma rota montada, e exibe um dashboard moderno e simples.

> **Spec:** piloto definido em conversa — sem spec formal prévia.
> **Branch:** `feat/rails-analytics-engine`

**Arquitetura:** Rails Engine isolado (`RailsAnalytics`) montado na host app em `/rails_analytics`. Coleta é same-origin, sem cookies: o tracker JS carrega um pixel GIF 1×1 com os dados em query params; o controller decodifica e grava uma linha em `page_views`. Privacidade first (estilo Umami): IP nunca é guardado cru — apenas hash com salt. Dashboard server-rendered, sem dependências JS de terceiros (gráfico em SVG gerado no servidor).

**Stack:** Ruby ≥ 3.0, Rails ≥ 7.0 (testado em 8.1), SQLite para o dummy/testes, ERB + CSS puro no dashboard.

## Restrições globais

- Sem cookies; session_id aleatório guardado em `localStorage`.
- IP sempre hasheado com `secret_key_base` como salt — nunca cru.
- Zero dependências runtime além do Rails.
- Suporte a Rails >= 7; compatível com SQLite/PostgreSQL/MySQL.
- Documentação e código da gem em português.

---

## Etapa 0 — Esqueleto da gem (Rails Engine)

### Task 0.1: Estrutura da gem + version + entry

**Files:**
- Create: `rails_analytics.gemspec`, `Gemfile`, `Rakefile`, `lib/rails_analytics/version.rb`, `lib/rails_analytics.rb`
- Test: `test/test_helper.rb`

**Interfaces:**
- Produces: constante `RailsAnalytics::VERSION`, require `rails_analytics`.

- [ ] **Step 1: Escrever gemspec e entry**

```ruby
# lib/rails_analytics/version.rb
module RailsAnalytics
  VERSION = "0.1.0"
end
```

```ruby
# lib/rails_analytics.rb
require "rails_analytics/version"
require "rails_analytics/engine" if defined?(Rails::Railtie)
```

```ruby
# rails_analytics.gemspec
require_relative "lib/rails_analytics/version"

Gem::Specification.new do |s|
  s.name        = "rails_analytics"
  s.version     = RailsAnalytics::VERSION
  s.summary     = "Analytics estilo Umami para Rails — coleta de tráfego e dashboard."
  s.description = "Engine Rails que coleta tráfego (pixel + tracker JS, sem cookies), salva no banco da host app e exibe dashboard simples."
  s.authors     = ["br4zz4"]
  s.homepage    = "https://github.com/br4zz4/rails-analytics"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.0"
  s.files       = Dir["lib/**/*", "app/**/*", "config/**/*", "db/**/*", "README.md", "MIT-LICENSE"]
  s.require_paths = ["lib"]
  s.add_dependency "rails", ">= 7.0"
end
```

- [ ] **Step 2: Rakefile + test helper**

```ruby
# Rakefile
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
end

task default: :test
```

```ruby
# test/test_helper.rb
require "minitest/autorun"
```

- [ ] **Step 3: Teste trivial + rodar**

```bash
bundle install && bundle exec rake test
```

Expected: PASS (suíte vazia ou teste de VERSION).

- [ ] **Step 4: Commit**

```bash
git add . && git commit -m "feat: skeleton da gem rails_analytics"
```

### Task 0.2: Engine + rotas montáveis

**Files:**
- Create: `lib/rails_analytics/engine.rb`, `config/routes.rb`

**Interfaces:**
- Produces: `RailsAnalytics::Engine` (isolate_namespace), mount point `/rails_analytics`.

- [ ] **Step 1: Engine**

```ruby
# lib/rails_analytics/engine.rb
module RailsAnalytics
  class Engine < ::Rails::Engine
    isolate_namespace RailsAnalytics
    config.generators do |g|
      g.test_framework :minitest
    end
  end
end
```

- [ ] **Step 2: Rotas (coleta + dashboard — vazias até as próximas tasks)**

```ruby
# config/routes.rb
RailsAnalytics::Engine.routes.draw do
end
```

- [ ] **Step 3: Commit**

```bash
git add . && git commit -m "feat: engine isolada com rotas montáveis"
```

---

## Etapa 1 — Coleta de tráfego

### Task 1.1: Modelo `PageView` + migração

**Files:**
- Create: `db/migrate/20260906000000_create_rails_analytics_page_views.rb`
- Create: `app/models/rails_analytics/page_view.rb`

**Interfaces:**
- Produces: `RailsAnalytics::PageView` com `self.table_name = "rails_analytics_page_views"`, colunas: `path`, `referrer`, `title`, `screen_width`, `screen_height`, `language`, `user_agent`, `ip_hash`, `session_id`, `viewed_at`.
- Consumes: nada.

- [ ] **Step 1: Migração**

```ruby
class CreateRailsAnalyticsPageViews < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_page_views do |t|
      t.string :path, null: false
      t.string :referrer
      t.string :title
      t.integer :screen_width
      t.integer :screen_height
      t.string :language
      t.string :user_agent
      t.string :ip_hash
      t.string :session_id
      t.datetime :viewed_at, null: false

      t.timestamps
    end

    add_index :rails_analytics_page_views, :viewed_at
    add_index :rails_analytics_page_views, :path
    add_index :rails_analytics_page_views, :session_id
  end
end
```

- [ ] **Step 2: Modelo**

```ruby
module RailsAnalytics
  class PageView < ActiveRecord::Base
    self.table_name = "rails_analytics_page_views"

    scope :since, ->(time) { where(arel_table[:viewed_at].gteq(time)) }

    def self.ip_hash_from(ip)
      Digest::SHA256.hexdigest("#{ip}#{Rails.application.secret_key_base}")
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add . && git commit -m "feat: modelo PageView e migração"
```

### Task 1.2: Controller de coleta (pixel GIF 1×1)

**Files:**
- Create: `app/controllers/rails_analytics/application_controller.rb`
- Create: `app/controllers/rails_analytics/analytics_controller.rb`
- Modify: `config/routes.rb`

**Interfaces:**
- Produces: `GET /rails_analytics/px.gif` → grava PageView, responde GIF transparente (Content-Type `image/gif`).
- Consumes: `RailsAnalytics::PageView`.

- [ ] **Step 1: Controller**

```ruby
module RailsAnalytics
  class ApplicationController < ActionController::Base
  end
end
```

```ruby
module RailsAnalytics
  class AnalyticsController < ApplicationController
    skip_before_action :verify_authenticity_token
    GRAY_1PX_GIF = Base64.decode64("R0lGODlhAQABAPAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==")

    def px
      PageView.create!(
        path:        params[:path].to_s[0, 500],
        referrer:    params[:referrer].to_s[0, 500].presence,
        title:       params[:title].to_s[0, 255].presence,
        screen_width:  params[:sw].to_i,
        screen_height: params[:sh].to_i,
        language:    params[:lang].to_s[0, 8].presence,
        user_agent:  request.user_agent.to_s[0, 255].presence,
        ip_hash:     PageView.ip_hash_from(request.remote_ip),
        session_id:  params[:sid].to_s[0, 64].presence,
        viewed_at:   Time.current
      )
      render plain: GRAY_1PX_GIF, content_type: "image/gif"
    rescue ActiveRecord::RecordInvalid
      head :bad_request
    end
  end
end
```

- [ ] **Step 2: Rotas**

```ruby
RailsAnalytics::Engine.routes.draw do
  get "px.gif" => "analytics#px"
end
```

- [ ] **Step 3: Commit**

```bash
git add . && git commit -m "feat: endpoint px.gif grava page views"
```

### Task 1.3:Tracker JS + helper de injeção

**Files:**
- Create:`app/assets/javascripts/rails_analytics/tracker.js`
- Create:`app/helpers/rails_analytics/application_helper.rb`

**Interfaces:**
- Produces: helper`rails_analytics_tracker_tag` (retorna `<script>` com caminho do tracker + opções).
- Consumes: rota`px.gif`.

Tracker (ES5, zero deps, não bloqueante):

```js
(function () {
  var KEY = "rails_analytics.sid";
  var sid = localStorage.getItem(KEY);
  if (!sid) { sid = Math.random().toString(36).slice(2) + Date.now().toString(36); localStorage.setItem(KEY, sid); }
  function track() {
    var el = document.querySelector('script[data-rails-analytics]');
    if (!el) return;
    var base = el.getAttribute('data-endpoint') || '/rails_analytics';
    var params = [
      'sid=' + encodeURIComponent(sid),
      'path=' + encodeURIComponent(location.pathname + location.search),
      'referrer=' + encodeURIComponent(document.referrer),
      'title=' + encodeURIComponent(document.title),
      'sw=' + screen.width, 'sh=' + screen.height,
      'lang=' + encodeURIComponent(navigator.language)
    ];
    var img = new Image();
    img.src = base + '/px.gif?' + params.join('&');
  }
  if (document.readyState === 'complete') track(); else window.addEventListener('load', track);
})();
```

Helper:

```ruby
module RailsAnalytics
  module ApplicationHelper
    def rails_analytics_tracker_tag(options = {})
      endpoint = options[:endpoint] || "/rails_analytics"
      tag.script(src: "#{endpoint}/tracker.js", data: { rails_analytics: true, endpoint: endpoint })
    end
  end
end
```

Server-side de `tracker.js` (evita conflito de asset pipeline — rota no engine):

```ruby
get "tracker.js" => "analytics#tracker"
# no controller:
def tracker
  render plain: TrackerScript.source, content_type: "application/javascript", layout: false
end
```

**Files adicionais:**
- Create: `app/models/rails_analytics/tracker_script.rb` (constante com o JS acima).

- [ ] **Commit**

```bash
git add . && git commit -m "feat: tracker js e helper de injeção"
```

### Task 1.4: Generator de instalação (copia migração + helper no host)

**Files:**
- Create: `lib/generators/rails_analytics/install/install_generator.rb`
- Create: `lib/tasks/rails_analytics_tasks.rake` (instalador de migração)

- [ ] **Step 1: Generator**

```ruby
module RailsAnalytics
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("../templates", __FILE__)

      def copy_migration
        copy_file "create_rails_analytics_page_views.rb",
                  "db/migrate/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_create_rails_analytics_page_views.rb"
      end

      def mount_engine
        route 'mount RailsAnalytics::Engine => "/rails_analytics"'
      end

      def inject_tracker
        layout = Dir["app/views/layouts/*.html.erb"].first
        return unless layout
        inject_into_file layout, before: "</head>" do
          "\n    <%= rails_analytics_tracker_tag %>\n"
        end
      end
    end
  end
end
```

- [ ] **Step 2: Rake task de instalação da migração**

```ruby
namespace :rails_analytics do
  desc "Copia a migração para a host app"
  task :install_migrations do
    RailsAnalytics::Engine.load_tasks
  end
end
```

Na prática usamos o `install:migrations` nativo do engine:

```bash
bin/rails rails_analytics:install:migrations
```

- [ ] **Step 3: Commit**

```bash
git add . && git commit -m "feat: generator de instalação"
```

---

## Etapa 2 — Dashboard de tráfego

### Task 2.1: Controller + queries agregadas

**Files:**
- Create: `app/controllers/rails_analytics/dashboards_controller.rb`

**Interfaces:**
- Produces: `GET /rails_analytics/` → `index` com `@stats` (hash de KPIs + séries).
- Consumes: `RailsAnalytics::PageView`.

```ruby
module RailsAnalytics
  class DashboardsController < ApplicationController
    def index
      @stats = DashboardStats.new(PageView)
      @stats.load
    end
  end
end
```

**Files adicionais:**
- Create: `app/models/rails_analytics/dashboard_stats.rb` — agrega em SQL puro:
  - views hoje, views últimos 7d, views 30d
  - visitantes únicos 30d (COUNT DISTINCT session_id)
  - séries diárias 30d (group by date)
  - top 10 páginas (30d)
  - top 10 referrers (30d)
  - top 8 user agents agrupados por browser (parse simples)
  - breakup móbile vs desktop (via `screen_width`)

- [ ] **Commit**

```bash
git add . && git commit -m "feat: queries agregadas do dashboard"
```

### Task 2.2: Views (KPIs + SVG chart + tabelas)

**Files:**
- Create: `app/views/rails_analytics/dashboards/index.html.erb`
- Create: `app/views/layouts/rails_analytics.html.erb`
- Create: `app/assets/stylesheets/rails_analytics/dashboard.css`

- [ ] **Step 1: Layout + CSS moderno (dark-mode friendly, tipografia clara, cards)**

- [ ] **Step 2: View com:**
  - 4 cards KPI (Hoje, 7 dias, Visitantes únicos 30d, Páginas/visita)
  - Gráfico de barras SVG das últimas 30 visitas diárias
  - Tabelas top páginas + top referrers
  - Minted badges de browser/device

- [ ] **Step 3: Rotas**

```ruby
root to: "dashboards#index"
```

- [ ] **Step 4: Commit**

```bash
git add . && git commit -m "feat: dashboard de tráfego"
```

---

## Etapa 3 — Verificação

- [ ] Criar dummy app `test/dummy` ou usar `rails new` temporário com a gem instalada via path
- [ ] Rodar migração, gerar views de teste feitas por request no pixel, carregar dashboard
- [ ] Cobertura mínima: testes de controller (px grava + responde GIF, inválido → 400) e de stats
- [ ] `bundle exec rake` verde
- [ ] README.md com instruções de uso
- [ ] Commit final + tag `v0.1.0`

---

## Pós-piloto (fora de escopo)

Campanhas/UTM, eventos e conversões, exclusão de tráfego próprio, multi-sitio, auth do dashboard, retenção de dados, geo/localização.