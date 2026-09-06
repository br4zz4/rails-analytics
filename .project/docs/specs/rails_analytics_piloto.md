---
title: Spec técnica — Coleta de tráfego e dashboard (rails_analytics)
spec: features/rails_analytics_trafego.md
created: 2026-09-06
updated: 2026-09-06
status: implementada
certainty: high
---

# Spec técnica — rails_analytics (piloto)

> **Papel**: Arquiteta (joana-arquiteta)
> **Feature**: `features/rails_analytics_trafego.md`
> **Plano**: `plans/20260906_rails_analytics_piloto.md`
> **Stack**: Ruby >= 3.0 · Rails >= 7.0 (testado em 8.1) · SQLite/PostgreSQL/MySQL

## 1. Visão geral

Gem `rails_analytics` como **Rails Engine isolado** (`RailsAnalytics::Engine`,
`isolate_namespace`), montado na host app em `/rails_analytics`. Coleta mesma-origem
via **pixel GIF 1×1 + tracker JS** (padrão Umami), **sem cookies**, armazenando em uma
tabela no banco da própria aplicação. Dashboard server-rendered (SVG puro), sem
dependências JS de terceiros e sem CDN.

## 2. Arquitetura

```
┌──────────────┐  tracker.js (carregado via <script> injetado no layout)
│  Navegador   │──────────────┐
└──────────────┘              ▼
            GET /rails_analytics/px.gif?sid=&path=&referrer=&title=&sw=&sh=&lang=
                              ▼
                  ┌──────────────────────────┐
                  │ AnalyticsController#px   │  create! PageView
                  │  (skip CSRF, GET ímpar)  │  ip_hash = SHA256(ip + secret_key_base)
                  └──────────┬───────────────┘
                             ▼
                  ┌──────────────────────────┐
                  │ rails_analytics_page_views│  tabela na DB da host app
                  └──────────┬───────────────┘
                             ▼
                  ┌──────────────────────────┐
                  │ DashboardController#index │  DashboardStats (SQL agregado)
                  │  + ChartBuilder (SVG)     │  KPIs + gráfico 30d + tabelas
                  └──────────────────────────┘
```

### Decisões de arquitetura (ADR resumido)

| Decisão | Alternativa descartada | Motivo |
|---------|------------------------|--------|
| **Pixel GIF 1×1** (GET) | POST fetch beacon | Mesmo padrão do Umami; funciona sem JS/CORS; GET com query params é simples e cacheável |
| **Sem cookies** (session_id em `localStorage`) | cookie de sessão | Privacidade first (GDPR-friendly), alinhado ao Umami |
| **IP hasheado** com salt | IP cru | Impossível reverter; `secret_key_base` como salt |
| **Tracker/CSS servidos pelo próprio engine** | Asset pipeline / CDN | Zero dependência de build da host app; rotas GET dedicadas |
| **SVG server-rendered** para o gráfico | Chart.js / npm | Sem JS de terceiros, sem CDN, carregamento instantâneo |
| **Isolate namespace + helper injetado** | helper manual | Isolamento do engine; `config.to_prepare` + `on_load(:action_view)` inclui o helper na host app |

## 3. Modelo de dados

### Tabela `rails_analytics_page_views`

| Coluna | Tipo | Restrições | Descrição |
|--------|------|------------|-----------|
| `id` | bigint PK | | |
| `path` | string | NOT NULL, index | caminho visitado (com query string) |
| `referrer` | string | nullable | origem do visitante |
| `title` | string | nullable | título da página |
| `screen_width` | integer | nullable | largura da tela |
| `screen_height` | integer | nullable | altura da tela |
| `language` | string | nullable | idioma (truncado em 8) |
| `user_agent` | string | nullable | UA do navegador (truncado em 255) |
| `ip_hash` | string | nullable | SHA-256(ip + secret_key_base) |
| `session_id` | string | nullable, index | identificador aleatório de sessão |
| `viewed_at` | datetime | NOT NULL, index | momento da visita |
| `created_at` / `updated_at` | datetime | | timestamps |

Índices: `viewed_at`, `path`, `session_id`.

### Modelo `RailsAnalytics::PageView`

- `self.table_name = "rails_analytics_page_views"`
- `validates :path, presence: true`
- `scope :since(time)` — filtra por `viewed_at >= time`
- `self.ip_hash_from(ip)` — `Digest::SHA256.hexdigest("#{ip}#{Rails.application.secret_key_base}")`

## 4. Use cases

### UC-01 — Coletar visita (tráfego)

**Atores**: Navegador (tracker JS).

1. O tracker (carregado no `load`) monta a URL do pixel com query params:
   `sid`, `path`, `referrer`, `title`, `sw`, `sh`, `lang`.
2. `AnalyticsController#px` (GET `/px.gif`, `skip_before_action :verify_authenticity_token`).
3. Normaliza: trunca campos (`path` 500, `referrer` 500, `title` 255, `lang` 8, `user_agent` 255),
   calcula `ip_hash`, define `viewed_at: Time.current`.
4. `PageView.create!` — em falha de validação → `rescue ActiveRecord::RecordInvalid` → **400**.
5. Sucesso → responde GIF transparente 1×1 (`image/gif`), corpo de 43 bytes.

**Regras**:
- `path` ausente/vazio → 400, nenhuma linha gravada (validação no modelo, `create!` explodindo → rescue).
- IP nunca persistido cru.

### UC-02 — Servir tracker JS

**Atores**: Navegador, helper do layout.

1. O layout da host app renderiza `<script src="/rails_analytics/tracker.js" data-rails-analytics data-endpoint="/rails_analytics" async>`.
2. `AnalyticsController#tracker` responde a constante `TrackerScript::SOURCE` com `content_type: "application/javascript"`.

**Regras**: o `data-endpoint` deve casar com o mount path (default `/rails_analytics`).

### UC-03 — Servir CSS do dashboard

**Atores**: Navegador (layout do dashboard).

1. `AnalyticsController#dashboard_css` lê `app/assets/stylesheets/rails_analytics/dashboard.css` do engine e responde `text/css`.

### UC-04 — Exibir dashboard

**Atores**: Usuário (dono do site).

1. GET `/rails_analytics` → `DashboardsController#index`.
2. `DashboardStats.call(PageView)` roda as agregações em SQL puro:
   - `views_today` — `viewed_at >= início do dia`
   - `views_7d` — `since(7.days.ago)`
   - `views_30d` — `since(30.days.ago)`
   - `unique_visitors_30d` — `COUNT(DISTINCT session_id)` em 30d
   - `pages_per_visit` — `views_30d / unique_session_30d` (2 casas; 0 se não houver sessões)
   - `daily_series` — `GROUP BY date(viewed_at)` preenchendo dias sem dados com 0
   - `top_pages` / `top_referrers` — top 10 por contagem
   - `devices` — desktop (`screen_width >= 768`) vs móvel (`< 768`)
3. `ChartBuilder` gera o SVG `<rect>` por dia (largura 800, 30 barras).
4. View ERB renderiza KPIs, gráfico, tabelas e breakdown; layout `rails_analytics.html.erb`.
5. Dashboard vazio → mensagens "sem dados", nunca 500.

### UC-05 — Instalar a gem

**Atores**: Desenvolvedor.

1. `bin/rails generate rails_analytics:install` copia a migração (timestamp atual),
   adiciona `mount RailsAnalytics::Engine => "/rails_analytics"` e injeta o tracker
   no primeiro `app/views/layouts/*.html.erb` (idempotente — pula se já existe).
2. `bin/rails db:migrate` cria a tabela.

## 5. Interface pública do engine

### Rotas (`config/routes.rb`)

```
GET /rails_analytics/px.gif       → analytics#px      (coleta)
GET /rails_analytics/tracker.js   → analytics#tracker (JS do tracker)
GET /rails_analytics/dashboard.css→ analytics#dashboard_css (CSS do dashboard)
GET /rails_analytics/             → dashboards#index  (dashboard)
```

### Helpers expostos à host app

```ruby
rails_analytics_tracker_tag(endpoint: "/rails_analytics")
# → <script src="/rails_analytics/tracker.js" data-rails-analytics data-endpoint="..." async>
```

### Classes expostas

| Classe | Responsabilidade |
|--------|------------------|
| `RailsAnalytics::Engine` | bootstrap, isolamento, precompile, helper injection |
| `RailsAnalytics::PageView` | modelo + validação + scope + ip_hash |
| `RailsAnalytics::TrackerScript` | fonte do tracker JS |
| `RailsAnalytics::DashboardStats` | agregações SQL do dashboard |
| `RailsAnalytics::ChartBuilder` | geração do SVG do gráfico |
| `RailsAnalytics::ApplicationHelper` | helper `rails_analytics_tracker_tag` |

## 6. Segurança e privacidade

- **CSRF**: `px` é GET sem `verify_authenticity_token` (intencional — coleta via imagem).
  Dashboard herda proteção do `ApplicationController` do engine.
- **IP**: nunca cru; hash com salt de `secret_key_base` (não reversível sem a chave).
- **Truncamento**: mitiga abuso de payload grande na query string.
- **Validação**: `path` obrigatório → rejeição 400 em payload inválido.
- **XSS**: ERB escapa output; dados do request são persistidos sem execução.
- **Sem cookies**: apenas `localStorage` para session_id — sem rastreio cross-site.

## 7. Requisitos não funcionais

- **Performance**: agregações em SQL puro (sem N+1); tabela indexada por `viewed_at`.
  Para escala futura: job de rollup diário (fora do escopo).
- **Compatibilidade**: Rails >= 7 (migração `[7.0]`), Ruby >= 3.0; SQLite/PostgreSQL/MySQL.
- **Dependências**: zero runtime além do Rails (sem jQuery, sem chart library).
- **Privacidade/LGPD-GDPR**: sem cookies, IP hasheado, dados na própria app.

## 8. Estratégia de teste

- **Unit**: `PageView.ip_hash_from` determinístico; validação de `path`.
- **Integração (dummy app, ActionDispatch::IntegrationTest)**:
  - `px.gif` grava page view completa e responde GIF.
  - `px.gif` sem path → 400, nada gravado.
  - `px.gif` com path > 500 → truncado.
  - `tracker.js` e `dashboard.css` servidos com content-type correto.
  - Dashboard renderiza KPIs, série, top páginas/referrers, breakdown e `svg`; vazio → sem erro.
- Suíte: 6 runs, 41 assertions (verde).

## 9. Fora de escopo (próximas iterações)

Campanhas/UTM, eventos custom, conversões, exclusão de bots/próprio tráfego,
multi-sitio, auth do dashboard, retenção/exportação, job de rollup para escala.