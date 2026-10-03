---
title: Dashboard — view de trajetórias por sessão
status: proposed
created: 2026-10-03
updated: 2026-10-03
owner: "@gporpino"
certainty: high
---

# Dashboard — view de trajetórias por sessão

> **TLDR**: Nova página "Trajetórias" no dashboard: cards por sessão (visit) mostrando a jornada ordenada do usuário — pageviews, cliques, scroll, forms — com setas entre os passos, hover com detalhes por passo e a origem (referrer) no cabeçalho.

## Contexto

Os dados já suportam trajetória completa sem migração:
- `Visit.find_or_create_for` agrupa eventos numa sessão (janela de 4h por `anonymity_key` rotação diária).
- O host (ex.: ya-site) já rastreia: CTAs (`data-ra-analytics` + `value`), `scroll-depth { mark }`, `form-submit { form }`, `outbound-click { target }`, `email-click`, `time-on-page { seconds }`.
- `Event.properties` jsonb guarda os detalhes por evento.

Falta a visão: "o que ESSE usuário fez" — hoje só há agregados.

## Objetivos

1. Página Journeys: lista paginada de sessões recentes em cards.
2. Card = jornada ordenada: chips (pageview → clique → scroll → ...) ligados por setas; hover/focus revela detalhes por passo (timestamp, propriedades, dispositivo).
3. Cabeçalho do card: origem (referrer domain), device/viewport, duração, nº de passos, UTM quando houver.
4. Filtro por evento: de `top_events`/tabela de eventos, link "ver trajetórias" → `?event=<nome>` lista só sessões com aquele evento.
5. Zero JS; tudo CSS (hover/focus) no padrão do dashboard.

## Fora de escopo

- Gráficos de funil, coohort, heatmap.
- Identificação entre dias (a key de anonimato rotaciona diariamente por desenho LGPD).
- Mudanças no tracker/coleta.

## Mudanças

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `lib/rails_analytics/stats.rb` | Modificar | `journeys(event:, page:, per_page:, since:)` — visits com events ordenados, filtro opcional por nome do evento. |
| `app/models/rails_analytics/journey.rb` | Criar | Serializer: visit → {origin, device, viewport, language, utm, duration, steps[] (kind, label, detail, time)}. |
| `app/controllers/rails_analytics/journeys_controller.rb` | Criar | `index` com filtros + paginação. |
| `config/routes.rb` + layout nav | Modificar | `GET journeys` + link "Trajetórias". |
| `app/views/rails_analytics/journeys/index.html.erb` | Criar | Cards com steps/setas; tooltip CSS; filtro. |
| `app/assets/stylesheets/rails_analytics/dashboard.css` | Modificar | `.ra-journey*` cards, chips, arcos de seta, tooltip. |
| `app/views/.../overview.html.erb` + `events.html.erb` | Modificar | Links "trajetórias" por evento nas tabelas. |
| locales pt-BR/en | Modificar | Chaves `journeys.*`. |
| tests | Criar/Modificar | Unit do serializer (formato dos steps), controller test, asserts. |
| CHANGELOG/README | Modificar | 1.2.0 — nova view. |

## Como verificar

1. `/rails_analytics/journeys` → cards das sessões recentes, jornada ordenada por tempo.
2. Hover/Tab num chip → detalhes do passo (timestamp, props).
3. Cabeçalho mostra origem (ex. `twitter.com`, `direct`), device, duração.
4. Na tabela de eventos, link roda para `/journeys?event=doacao-click` filtrando.
5. `bundle exec rake test` + dummy suite verdes.

## Documentação

- `README.md` (seção do dashboard), `CHANGELOG.md` (1.2.0).
