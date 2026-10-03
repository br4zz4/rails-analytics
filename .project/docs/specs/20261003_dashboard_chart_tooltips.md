---
title: Dashboard — tooltip nos nós do gráfico e legibilidade
status: proposed
created: 2026-10-03
updated: 2026-10-03
owner: "@gporpino"
certainty: high
---

# Dashboard — tooltip nos nós do gráfico e legibilidade

> **TLDR**: Tooltip CSS-only (zero JS) nos nós do gráfico de visitas mostrando `data · N visitas`, com área de hover maior, rótulos de data no eixo X e acessibilidade por teclado — sem introduzir JavaScript.

## Contexto

O gráfico de visitas por dia é um SVG server-rendered gerado por `ChartBuilder` (`app/models/rails_analytics/chart_builder.rb`). Cada nó é um `<circle r="3">` sem interação: passar o mouse não revela o valor do dia, e não há rótulos de data no eixo X — o número exato de cada dia só aparece na tabela de visitas.

O gem se posiciona como **zero client-side JS** (README). A melhoria preserva esse princípio: tooltip estilizado via **CSS puro**, acionado por `:hover` e `:focus`, sem `<script>`.

Boas práticas aplicadas (NN/g, USWDS, LogRocket): tooltip suplementar (o dado completo já está na tabela), acionável também por teclado/foco, contraste ≥ 4.5:1 em light e dark mode.

## Objetivos

1. Tooltip por nó mostrando `data · N visitas` ao passar o mouse, sem JS.
2. Área de hover maior que o círculo visível (`r=3` é pequeno demais para mirar).
3. Rótulos de data no eixo X: primeira e última data + viradas de mês (espaçadas o suficiente para não colidir).
4. Acessibilidade: cada nó com `aria-label` e focável (Tab) — tooltip também aparece no `:focus`.

## Fora de escopo

- Qualquer JavaScript (Chartkick etc.) — pertence à spec v2 (`20260906_rails_analytics_v2`).
- Funnels, heatmaps, export CSV, novas métricas, mudanças de modelo de dados.
- Trocar o SVG por biblioteca de charting.

## Mudanças

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| `app/models/rails_analytics/chart_builder.rb` | Modificar | Cada nó vira `<g class="ra-dot" tabindex="0" role="img" aria-label="...">` com: círculo visível (r=3), círculo de hit area invisível (r=12), tooltip (`<rect>` + `<text>`) calculado server-side, acima do nó (abaixo se colidir com o topo). Rótulos do eixo X (primeira/última data + viradas de mês). |
| `app/assets/stylesheets/rails_analytics/dashboard.css` | Modificar | `.ra-dot` (cursor), `.ra-tooltip` oculto (`opacity: 0`, `pointer-events: none`) visível em `:hover`/`:focus-within`; cores via classes + CSS vars, contraste ok em dark mode; `.ra-axis` para rótulos. |
| `config/locales/rails_analytics.pt-BR.yml` | Modificar | Chave `chart.tooltip` com pluralização (`one`/`other`). |
| `config/locales/rails_analytics.en.yml` | Modificar | Mesmas chaves em inglês. |
| `test/models/chart_builder_test.rb` | Criar | Unit test do `ChartBuilder`: `aria-label` correto, hit area, rótulos de eixo, sem `<script>`. |
| `test/controllers/dashboards_controller_test.rb` | Modificar | Overview contém `ra-dot`, `aria-label`, `ra-axis`; nenhum `<script>` no HTML. |
| `README.md` / `CHANGELOG.md` | Modificar | Mencionar tooltip no gráfico; changelog 1.1.0. |

## Como verificar

1. `/analytics` → mouse sobre um nó → tooltip `12/09 · 234 visitas`.
2. Tab até um nó → tooltip no `:focus`; screen reader lê o `aria-label`.
3. Dark mode → tooltip legível.
4. HTML renderizado não contém `<script>` novo.
5. `bin/rails test` verde.

## Documentação

| Arquivo | Ação |
|---------|------|
| `README.md` | Atualizar (tooltip, curto). |
| `CHANGELOG.md` | Atualizar (1.1.0). |
| `.project/docs/learnings/` | Registrar técnica de tooltip CSS-only em SVG (opcional). |
