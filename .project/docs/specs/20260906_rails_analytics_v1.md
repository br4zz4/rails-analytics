---
title: rails_analytics v1 — Analytics engine completo (cookie-less, LGPD-compliant)
status: proposed
created: 2026-09-06
updated: 2026-09-06
owner: "@gporpino"
certainty: high
---

# rails_analytics v1

> **TLDR**: Reescrever o piloto `rails_analytics` como uma engine Rails completa: tracker JS cookie-less com signed token, endpoint de coleta com IP masking + chave de anonimato rotativa, queries agregadas (Stats), dashboard 3 páginas em pt-BR com I18n, auth configurável, rate limiting, retention job, install generator. Tudo TDD.

## Contexto

O piloto (`v0.1.0`, 8 commits) validou a arquitetura: pixel GIF, `page_views`, dashboard SVG server-side. Agora evoluímos para uma gem generalista (não só campanha), com:

- Modelo de dados mais rico: `visits` + `events` (substitui `page_views`)
- Anonimato por design: sem cookies, sem fingerprint, IP mascarado, chave de anonimato rotativa (sal diário)
- Conformidade LGPD/ANPD/Marco Civil como propriedade arquitetural, não configuracional
- Coleção via POST + sendBeacon com signed token (sobrevive a page unload)
- UTM parse no insert, 5 colunas dedicadas
- Dashboard RESTful com 3 views (overview, events, visits), I18n pt-BR + en
- Auth callback configurável (symbol ou callable), rate limiting com rack-attack
- Retention job (6 meses, Marco Civil art. 15)
- Generator que monta a engine, copia migrations, pina o tracker no importmap

**Princípio arquitetural**: toda leitura é agregada. Nenhuma row individual é exposta. O dashboard é READ-ONLY sobre dados agrupados por dia.

## Objetivos

1. **Tracker JS cookie-less**: script servido via Propshaft/importmap, ~3 KB, sem cookies, sem localStorage, sem fingerprint. Coleta: path, referrer_domain, device_type (coarse), viewport, language, nonce. Envia via POST com signed token; sendBeacon no unload.
2. **Identity key anônima**: `SHA256(masked_ip + coarse_UA_bucket + daily_salt)`. Salt rotaciona diariamente (Rails.cache → fallback `secret_key_base + date`). Impossível cruzar dias ou recuperar IP.
3. **IP masking no edge**: IPv4 → último octeto zero; IPv6 → últimos 80 bits zero. IP real nunca armazenado.
4. **Collection endpoint**: `POST /analytics/collect` — valida signed token, mascara IP, deriva chave, cria/atualiza visit (janela de 4h), insere events. Rate limit: 20 req/min por masked IP via rack-attack. Responde 204. Nunca levanta exceção em payload malformado.
5. **UTM no insert**: extrai `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content` do `landing_page_path` e armazena em colunas dedicadas na `visits`.
6. **Stats agregado**: classe `Stats` com métodos que retornam apenas hashes/arrays agregados. Nenhuma row individual.
7. **Dashboard RESTful**: 3 views (overview `/`, events `/events`, visits `/visits`). Gráfico SVG server-side para visitas/dia; tabelas HTML para o resto. I18n pt-BR + en. CSS próprio, sem Tailwind.
8. **Auth configurável**: `config.auth_callback` aceita Symbol (`:authenticate_admin!`) ou callable (`-> { ... }`). `before_action` condicional só nas rotas de dashboard.
9. **Rate limiting**: rack-attack throttle no endpoint de coleta (20 req/min por masked IP).
10. **Retention job**: `RetentionJob` purga visits + events > 6 meses em batches. Idempotente.
11. **Install generator**: `rails generate rails_analytics:install` — copia migrations, monta engine em `routes.rb`, cria initializer, adiciona pin do tracker no `importmap.rb`.
12. **Testes TDD**: Minitest, dummy app. Cobertura: IpMask, Identity, coleta, Stats, dashboard, auth, rate limit, retention, segurança (sem vazamento de PII/tokens no HTML).

## Fora de escopo

- Geocoding (coluna `country` existe no schema mas sem lógica — stub para v2)
- Chartkick / gráficos JS interativos (v2)
- Eventos custom específicos do host (`scroll-depth`, `form-start`, `form-drop` como observers JS — a API `track()` existe, mas os observers são responsabilidade do host)
- Export CSV (mesmo agregado)
- Filtros por período custom no dashboard (usa `config.since_default`)
- Alertas / notificações
- Multi-tenancy

## Mudanças

### Modelos e migrations

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `db/migrate/XXXX_create_rails_analytics_visits.rb` | Criar | `id`, `anonymity_key` (string, indexed), `masked_ip` (string), `referrer_domain` (string), `landing_page_path` (text), `device_type` (string), `viewport` (string), `language` (string), `started_at` (datetime, indexed), `country` (string, nullable), `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content` (all nullable strings). Índice composto: `[anonymity_key, started_at]`. |
| `db/migrate/XXXX_create_rails_analytics_events.rb` | Criar | `id`, `visit_id` (FK, indexed), `name` (string, indexed), `properties` (jsonb, default `{}`), `time` (datetime, indexed). Índice composto: `[name, time]`. GIN index em `properties`. |
| `db/migrate/XXXX_create_rails_analytics_daily_salts.rb` | Criar | `id`, `date` (date, unique, indexed), `salt` (string). |
| `app/models/rails_analytics/visit.rb` | Reescrever | Substitui `page_view.rb`. `has_many :events, dependent: :delete_all`. Scopes: `since(t)`, `for_key(key)`. |
| `app/models/rails_analytics/event.rb` | Criar | `belongs_to :visit`. Scopes: `since(t)`, `named(name)`. |
| `app/models/rails_analytics/daily_salt.rb` | Criar | `.for_date(date)` — busca ou cria salt do dia. |

### Lib (core logic)

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `lib/rails_analytics.rb` | Reescrever | Entry point, require engine + configuration + ip_mask + identity + stats. |
| `lib/rails_analytics/engine.rb` | Reescrever | Engine atualizada com novos controllers, rotas, helpers. |
| `lib/rails_analytics/version.rb` | Atualizar | `0.1.0` → `1.0.0`. |
| `lib/rails_analytics/configuration.rb` | Reescrever | `auth_callback` (symbol/callable), `mount_path` (default `/analytics`), `since_default` (default `30.days.ago`). |
| `lib/rails_analytics/ip_mask.rb` | Criar | `IpMask.mask(ip_string)` → masked string. IPv4: último octeto → 0. IPv6: últimos 80 bits → 0. |
| `lib/rails_analytics/identity.rb` | Criar | `Identity.key(masked_ip:, user_agent:, date:)` → `SHA256(masked_ip + coarse_ua_bucket + daily_salt)`. Coarse UA bucket: extrai browser + OS family do user_agent (regex simples, sem gem). |
| `lib/rails_analytics/stats.rb` | Reescrever | Evolui `dashboard_stats.rb`. Métodos: `visits_by_day`, `unique_visitors_by_day`, `total_visits`, `total_unique_visitors`, `total_events`, `top_sources`, `top_events`, `event_counts_by_name`, `events_by_name`, `bounce_rate`, `utm_breakdown`, `devices`. Todos recebem `since:` keyword. Retornam hashes/arrays agregados. |

### Controllers

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/controllers/rails_analytics/application_controller.rb` | Reescrever | `before_action :authenticate!` condicional (só dashboard). Método `authenticate!` chama o callback configurado. |
| `app/controllers/rails_analytics/analytics_controller.rb` | Reescrever | `collect` (POST): valida signed token, mascara IP, deriva identity key, upsert visit, insere events, 204. `tracker` (GET): serve o JS. `token` (GET): gera signed token (TTL 5 min). |
| `app/controllers/rails_analytics/dashboards_controller.rb` | Reescrever | `overview` (GET /), `events` (GET /events), `visits` (GET /visits). Carrega `@stats` via `Stats`. |

### Views

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/views/layouts/rails_analytics.html.erb` | Reescrever | Layout com nav (overview, events, visits), footer LGPD, CSS inline. Labels via I18n. |
| `app/views/rails_analytics/dashboards/overview.html.erb` | Reescrever | KPIs (visits, unique, events, bounce), SVG chart (visitas/dia), top sources, top events, UTM table, devices. |
| `app/views/rails_analytics/dashboards/events.html.erb` | Criar | Tabela agregada por dia: date, event name, count. Filtro por event name. Paginação. |
| `app/views/rails_analytics/dashboards/visits.html.erb` | Criar | Tabela agregada por dia: date, visits, unique visitors, top source. Paginação. |
| `app/assets/stylesheets/rails_analytics/dashboard.css` | Reescrever | CSS próprio, expandido para cobrir novas views. Sem Tailwind. |

### JavaScript

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/assets/javascripts/rails_analytics/tracker.js` | Reescrever | Cookie-less tracker. Coleta: path, referrer_domain, device_type, viewport, language, nonce. Envia POST com signed token. sendBeacon no `pagehide`. API: `window.RailsAnalytics.track(name, props)`. Batched send a cada 10s ou 10 eventos. |

### Generator

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `lib/generators/rails_analytics/install/install_generator.rb` | Reescrever | Copia migrations, monta engine em `routes.rb`, cria initializer, adiciona pin no `importmap.rb`, instruções pós-install. |
| `lib/generators/rails_analytics/install/templates/initializer.rb` | Criar | Template do initializer com todas as opções de configuração comentadas. |

### Job

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/jobs/rails_analytics/retention_job.rb` | Criar | `perform` → `find_in_batches` em visits > 6 meses, deleta events + visits. Loga resumo. Idempotente. |

### Config

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `config/routes.rb` | Reescrever | Dashboard: `GET /`, `GET /events`, `GET /visits`. Coleta: `POST /collect`, `GET /tracker.js`, `GET /token`, `GET /dashboard.css`. |
| `config/locales/rails_analytics.pt-BR.yml` | Criar | Labels pt-BR. |
| `config/locales/rails_analytics.en.yml` | Criar | Labels en. |
| `rails_analytics.gemspec` | Atualizar | Atualizar versão, descrição, garantir `rails >= 7.0`. |

### Testes

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `test/lib/ip_mask_test.rb` | Criar | IPv4 e IPv6 masking. |
| `test/lib/identity_test.rb` | Criar | Mesma entrada → mesma chave; salt diferente → chave diferente; irreversibilidade. |
| `test/controllers/analytics_controller_test.rb` | Reescrever | POST válido → 204 + rows; malformado → 204 sem exceção; sem token → 401; rate limit. |
| `test/controllers/dashboards_controller_test.rb` | Reescrever | Sem auth → redirect; com auth → 200; HTML sem vazamento de PII/tokens. |
| `test/models/stats_test.rb` | Reescrever | Todos os métodos com dados semeados. Bounce rate = 0.75 (3 sem events + 1 com). |
| `test/jobs/retention_job_test.rb` | Criar | Purga > 6 meses, preserva recentes. |
| `test/dummy/` | Atualizar | Dummy app com rotas, importmap, rack-attack. |

## Como verificar

1. **Testes**: `bin/rails test` — todos os testes passam (Minitest, dummy app).
2. **Integração manual na dummy app**:
   - Acessar `/analytics/tracker.js` → JS servido com fingerprint.
   - POST `/analytics/collect` com payload válido + token → 204, rows em `visits` + `events`.
   - Acessar `/analytics/` → dashboard renderiza KPIs, SVG chart, tabelas.
   - Acessar `/analytics/events` e `/analytics/visits` → tabelas agregadas.
   - Sem auth → redirect para login do host.
3. **Segurança**:
   - HTML do dashboard não contém `anonymity_key`, `masked_ip`, ou signed token.
   - Payload malformado não quebra o endpoint (204, loga métrica).
   - Rate limit: >20 req/min de um mesmo masked IP → 429.
4. **Retenção**: rodar `RetentionJob.perform_now` → dados > 6 meses são deletados, recentes preservados.
5. **Generator**: `rails generate rails_analytics:install` em um app limpo → migrations copiadas, engine montada, initializer criado, pin no importmap.

## Documentação

| Arquivo | Ação |
|---------|------|
| `README.md` | Reescrever — install, mount, auth config, compliance section, tracker API, "add a new metric" guide. |
| `CHANGELOG.md` | Atualizar — v1.0.0 entry. |
| `.project/docs/learnings/` | Criar learnings da migração piloto → v1. |