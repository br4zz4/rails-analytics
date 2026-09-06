---
title: Rails Analytics — Coleta de tráfego e dashboard (piloto)
created: 2026-09-06
updated: 2026-09-06
status: implementado
certainty: high
---

# Feature: Coleta de tráfego e dashboard — rails_analytics

> **Papel**: Product Owner (igor-po)
> **Status**: ✅ implementado no piloto v0.1.0

## História de usuário

**US-01 — Coletar tráfego sem cookies**

> Como **dono de um site Rails**, quero **coletar visitas às páginas sem usar cookies**,
> para **entender meu tráfego respeitando a privacidade dos visitantes** (estilo Umami).

**US-02 — Visualizar dashboard de tráfego**

> Como **dono de um site Rails**, quero **ver métricas de tráfego em um dashboard**
> moderno e simples, para **tomar decisões sem depender de serviços externos**.

**US-03 — Instalar facilmente**

> Como **desenvolvedor Rails**, quero **instalar a gem com poucos comandos**,
> para **ter analytics rodando na minha aplicação em minutos**.

## Critérios de aceite (Gherkin)

### US-01 — Coleta de tráfego

```gherkin
Cenário: Visita gera uma page view
  Dado que o tracker está injetado no layout
  Quando o visitante acessa a página "/blog/hello"
  Então um request GET é enviado ao endpoint "/rails_analytics/px.gif"
  E uma linha é gravada em "rails_analytics_page_views"
  E o campo path é "/blog/hello"
  E o campo session_id é preenchido
  E o campo viewed_at é preenchido

Cenário: Endpoint retorna pixel 1x1 transparente
  Dado que o visitante dispara o pixel
  Quando a request é processada
  Então a resposta tem content-type "image/gif"
  E o corpo é um GIF transparente de 1x1

Cenário: Request sem path é rejeitada
  Dado que uma request chega ao px.gif
  Quando o parâmetro "path" está ausente ou vazio
  Então a resposta é 400 Bad Request
  E nenhuma linha é gravada

Cenário: IP nunca é armazenado cru
  Dado que uma page view é gravada
  Então o campo ip_hash contém um SHA-256 com salt
  E o IP real não aparece na tabela

Cenário: Campos longos são truncados
  Dado que o path enviado tem mais de 500 caracteres
  Quando a page view é gravada
  Então o campo path tem exatamente 500 caracteres
```

### US-02 — Dashboard

```gherkin
Cenário: Dashboard mostra KPIs
  Dado que existem page views nos últimos 30 dias
  Quando acesso "/rails_analytics"
  Então vejo o total de visitas hoje
  E o total de visitas em 7 dias
  E o total de visitantes únicos em 30 dias
  E a média de páginas por visita

Cenário: Dashboard mostra gráfico de 30 dias
  Dado que existem page views nos últimos 30 dias
  Quando acesso "/rails_analytics"
  Então vejo um gráfico de barras com a distribuição diária
  E o gráfico é renderizado no servidor (SVG), sem JS de terceiros

Cenário: Dashboard mostra top páginas e referências
  Dado que existem page views nos últimos 30 dias
  Quando acesso "/rails_analytics"
  Então vejo a lista das 10 páginas mais visitadas
  E a lista das 10 principais referências

Cenário: Dashboard mostra breakdown de dispositivos
  Dado que existem page views com resolução de tela
  Quando acesso "/rails_analytics"
  Então vejo o total de visitas desktop
  E o total de visitas móvel

Cenário: Dashboard vazio não quebra
  Dado que não existe nenhuma page view
  Quando acesso "/rails_analytics"
  Então a página renderiza com mensagens de "sem dados"
  E sem erro de servidor
```

### US-03 — Instalação

```gherkin
Cenário: Generator de instalação
  Dado que a gem está no Gemfile
  Quando rodo "bin/rails generate rails_analytics:install"
  Então a migração é copiada para "db/migrate/"
  E a rota "mount RailsAnalytics::Engine => \"/rails_analytics\"" é adicionada
  E a tag do tracker é injetada no <head> do layout

Cenário: Tracker é servido pela própria gem
  Dado que o engine está montado
  Quando o navegador requisita "/rails_analytics/tracker.js"
  Então recebe JavaScript com content-type "application/javascript"
  E o script contém a lógica de coleta e o session_id em localStorage
```

## Fora de escopo (pós-piloto)

- Campanhas/UTM, eventos e conversões
- Exclusão de tráfego próprio e bot
- Multi-sitio e autenticação do dashboard
- Retenção de dados e exportação
- Geo/localização