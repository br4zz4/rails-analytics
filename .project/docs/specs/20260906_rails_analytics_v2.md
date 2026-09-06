---
title: rails_analytics v2 — Geocoding, Chartkick, eventos do host, export
status: proposed
created: 2026-09-06
updated: 2026-09-06
owner: "@gporpino"
certainty: medium
---

# rails_analytics v2

> **TLDR**: Funcionalidades diferidas da v1: geocoding (country real via MaxMind/CF-IPCountry), suporte opcional a Chartkick no dashboard, observers JS para eventos do host (scroll-depth, form-start, form-drop), export CSV agregado, e otimizações de performance.

## Contexto

A v1 entrega o motor de analytics completo: coleta anônima, identity key rotativa, stats agregados, dashboard 3 páginas, auth, rate limiting, retenção. A v2 adiciona funcionalidades que enriquecem o dashboard sem alterar a arquitetura core:

- **Geocoding**: a coluna `country` já existe no schema. Preenchê-la com país real derivado do IP (antes de mascarar) via header `CF-IPCountry` (Cloudflare) ou fallback MaxMind GeoLite2.
- **Chartkick**: integração condicional — se a gem `chartkick` estiver no Gemfile do host, o dashboard usa gráficos JS interativos; senão, mantém SVG + tabelas HTML.
- **Eventos do host**: implementar os observers JS para `scroll-depth`, `form-start:{slug}`, `form-drop:{slug}` como parte do tracker (opcional, ativado via config).
- **Export CSV**: download de dados agregados (visitas/dia, eventos/dia). Apenas agregado, nunca row-level. LGPD-compliant.
- **Performance**: índices adicionais conforme volume real, particionamento por mês (opcional), cache de queries Stats.

Cada feature é independente e pode ser implementada em qualquer ordem.

## Objetivos

1. **Geocoding**: Preencher `country` com código ISO 3166-1 alpha-2, derivado de `CF-IPCountry` (preferido, zero latência) ou MaxMind GeoLite2 (fallback offline). O IP é mascarado DEPOIS de derivar o país. Nunca armazenar IP real.
2. **Chartkick opcional**: `Stats` expõe dados em formato compatível com Chartkick. As views detectam `defined?(Chartkick)` e renderizam `line_chart`, `bar_chart`, `pie_chart`. Fallback: SVG (linha) + tabelas HTML.
3. **Eventos do host no tracker**: `RailsAnalytics.init({ trackScrollDepth: true, trackForms: true })` ativa observers de scroll (25/50/75/100) e form (focus → `form-start:{name}`, blur sem submit → `form-drop:{name}`). Não-PII, apenas o `name` attribute do form.
4. **Export CSV agregado**: botão "Exportar CSV" em cada view do dashboard. Gera CSV com dados agregados (mesmo que a tabela visível). Rate-limited. Headers LGPD no CSV ("Dados agregados e anônimos — retenção 6 meses").
5. **Otimizações**: índices parciais para queries comuns, ` MATERIALIZED VIEW` para stats diários (opcional, via generator), cache `Rails.cache` nos métodos Stats com TTL configurável.

## Fora de escopo

- Identificação de cidade/região (só país)
- Funnels / goal tracking
- Session recordings / heatmaps
- Segmentação por propriedades de evento (além do `name`)
- Integração com Google Ads / Meta Ads
- Alertas em tempo real
- Multi-tenancy / múltiplos sites na mesma instância

## Mudanças

### Geocoding

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `lib/rails_analytics/geocoding.rb` | Criar | `Geocoding.country_from(request)` — tenta `CF-IPCountry`, fallback MaxMind (se DB presente), retorna `nil` se indisponível. |
| `app/models/rails_analytics/visit.rb` | Modificar | `country` populado no insert via `Geocoding`. |
| `config/initializer` template | Modificar | `config.geocoding_db_path` opcional. |
| `README.md` | Modificar | Instruções para baixar GeoLite2. |

### Chartkick

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/helpers/rails_analytics/chart_helper.rb` | Criar | `chart_for(type, data, opts)` — renderiza Chartkick se disponível, fallback SVG/tabela. |
| `app/views/rails_analytics/dashboards/overview.html.erb` | Modificar | Substituir SVG inline por `chart_helper`. |
| `lib/rails_analytics/stats.rb` | Modificar | Métodos adicionais que retornam arrays `[[label, value], ...]` compatíveis com Chartkick. |
| `gemspec` | Modificar | `s.add_development_dependency "chartkick"` (só dev/test). |

### Eventos do host (tracker JS)

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/assets/javascripts/rails_analytics/tracker.js` | Modificar | `init(opts)` com `trackScrollDepth` e `trackForms`. IntersectionObserver para scroll. `focus`/`blur` listeners para forms. |
| `README.md` | Modificar | Documentar API `init()` e eventos disparados. |

### Export CSV

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/controllers/rails_analytics/exports_controller.rb` | Criar | `visits` e `events` actions. Gera CSV com `send_data`. Rate-limited. |
| `config/routes.rb` | Modificar | `GET /exports/visits`, `GET /exports/events`. |
| `app/views/rails_analytics/dashboards/*.html.erb` | Modificar | Botão "Exportar CSV" em cada view. |

### Otimizações

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `db/migrate/XXXX_add_performance_indexes.rb` | Criar | Índices parciais: `visits (started_at) WHERE started_at > ...`, `events (time, name) WHERE time > ...`. |
| `lib/generators/rails_analytics/optimize/` | Criar | Generator opcional para criar materialized view de stats diários. |
| `lib/rails_analytics/stats.rb` | Modificar | `Rails.cache.fetch` com TTL configurável para queries caras. |
| `lib/rails_analytics/configuration.rb` | Modificar | `config.stats_cache_ttl` (default `5.minutes`). |

## Como verificar

1. **Geocoding**: request com header `CF-IPCountry: BR` → `visit.country == "BR"`. Sem header e sem GeoLite2 → `country == nil`.
2. **Chartkick**: host com `chartkick` no Gemfile → gráficos JS; host sem → SVG + tabelas. Nenhum erro em ambos os casos.
3. **Eventos do host**: `RailsAnalytics.init({ trackScrollDepth: true })` → scroll 50% dispara `track("scroll-depth", { mark: 50 })`.
4. **Export CSV**: GET `/analytics/exports/visits` → CSV com dados agregados, header LGPD. Sem auth → redirect.
5. **Performance**: queries Stats com e sem cache → segunda chamada significativamente mais rápida.

## Documentação

| Arquivo | Ação |
|---------|------|
| `README.md` | Atualizar — seções de geocoding, Chartkick, eventos do host, export, otimizações. |
| `CHANGELOG.md` | Atualizar — v2.0.0 entry. |
| `.project/docs/learnings/` | Atualizar com aprendizados da v2 (geocoding, Chartkick integration, observers). |