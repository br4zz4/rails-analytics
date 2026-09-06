# Rails Analytics

Analytics estilo [Umami](https://umami.is) para aplicações Rails — coleta de tráfego
**sem cookies** (privacy-first), salva no banco da sua própria aplicação e exibe um
dashboard moderno, simples e server-rendered (zero JS de terceiros).

## Como funciona

```
┌─────────────┐   tracker.js (injectado no layout)
│  Navegador  │──────────────────────────────►  GET /rails_analytics/px.gif?sid=...&path=...&...
└─────────────┘                                    │
                                                   ▼
                                        ┌──────────────────────┐
                                        │ AnalyticsController  │  grava PageView
                                        │  rails_analytics_    │  (IP hasheado)
                                        └──────────┬───────────┘
                                                   ▼
                                        ┌──────────────────────┐
                                        │   rails_analytics_   │  tabela no seu banco
                                        │   page_views         │
                                        └──────────┬───────────┘
                                                   ▼
                                        ┌──────────────────────┐
                                        │  Dashboard em        │  GET /rails_analytics
                                        │  /rails_analytics    │  KPIs + gráfico + tabelas
                                        └──────────────────────┘
```

1. O **tracker JS** (injetado pelo generator no `<head>` do layout) coleta no navegador:
   `path`, `referrer`, `title`, resolução de tela, idioma e um `session_id` aleatório
   guardado em `localStorage` (sem cookies).
2. No `load` da página, o tracker dispara um request para o **pixel 1×1 transparente**
   (`px.gif`) com os dados na query string — mesmo padrão do Umami, sem CORS (same-origin).
3. O engine grava uma linha em `rails_analytics_page_views`, **hasheando o IP**
   (nunca guarda o IP cru) e truncando campos longos.
4. O **dashboard** em `/rails_analytics` mostra as métricas agregadas em SQL puro.

## Requisitos

- Ruby >= 3.0
- Rails >= 7.0 (testado em 8.1)
- Banco: SQLite, PostgreSQL ou MySQL (qualquer banco suportado pelo Active Record)

## Instalação

### 1. Adicione a gem

```ruby
# Gemfile
gem "rails_analytics"
```

```bash
bundle install
```

### 2. Rode o generator de instalação

```bash
bin/rails generate rails_analytics:install
```

O generator faz 3 coisas:

| Ação | Arquivo | Detalhe |
|------|---------|---------|
| Copia a migração | `db/migrate/xxx_create_rails_analytics_page_views.rb` | cria a tabela `rails_analytics_page_views` |
| Monta o engine | `config/routes.rb` | adiciona `mount RailsAnalytics::Engine => "/rails_analytics"` |
| Injeta o tracker | `app/views/layouts/*.html.erb` | adiciona `<%= rails_analytics_tracker_tag %>` no `<head>` do primeiro layout |

### 3. Migre o banco

```bash
bin/rails db:migrate
```

Pronto! A coleta é automática e o dashboard fica em **`/rails_analytics`**.

## Uso

### Dashboard

Acesse `http://localhost:3000/rails_analytics`:

- **KPIs**: visitas hoje, visitas 7 dias, visitantes únicos 30d, páginas/visita
- **Gráfico**: visitas por dia (últimos 30 dias) — SVG do lado do servidor, sem JS
- **Tabelas**: páginas mais visitadas e principais referências (top 10)
- **Dispositivos**: breakdown desktop vs. móvel (via resolução de tela)

Tema claro/escuro automático (via `prefers-color-scheme`).

### Endpoint do tracker personalizado

Se você quiser montar o engine em outro caminho:

```ruby
# config/routes.rb
mount RailsAnalytics::Engine => "/analytics"
```

```erb
<!-- layout -->
<%= rails_analytics_tracker_tag endpoint: "/analytics" %>
```

> ⚠️ O `endpoint:` do helper deve bater com o caminho onde o engine foi montado.

### Desativar a coleta em ambientes específicos

```erb
<% unless Rails.env.local? %>
  <%= rails_analytics_tracker_tag %>
<% end %>
```

## Privacidade

- **Sem cookies** — identificador de sessão apenas em `localStorage` (expira com o navegador).
- **IP hasheado** com `secret_key_base` (SHA-256) — impossível reverter sem a chave da app.
- Não rastreia cliques, campos de formulário nem conteúdo digitado.
- Sem dependência de CDN — tudo roda dentro da sua aplicação.

## Tabela criada

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `path` | string, NOT NULL | caminho visitado (ex: `/blog/hello?x=1`) |
| `referrer` | string | origem do visitante (cabeçalho `Referer`) |
| `title` | string | título da página |
| `screen_width` / `screen_height` | integer | resolução de tela |
| `language` | string | idioma do navegador |
| `user_agent` | string | User-Agent (truncado em 255) |
| `ip_hash` | string | SHA-256 do IP com salt |
| `session_id` | string | identificador aleatório de sessão |
| `viewed_at` | datetime, NOT NULL | momento da visita |

Índices em `viewed_at`, `path` e `session_id`.

## Testes

```bash
# na raiz da gem
bundle install
cd test/dummy && bin/rails db:migrate RAILS_ENV=test && cd ../..
bin/rails test
```

## App demo (ver funcionando)

Veja [rails-analytics-demo](https://github.com/oporpino/rails-analytics-demo) — um app
Rails pronto com a gem configurada, dados de exemplo e instruções passo a passo para
rodar e navegar vendo as visitas aparecerem no dashboard.

## Roadmap (fora do piloto)

- Campanhas/UTM, eventos e conversões
- Exclusão de tráfego próprio e bot
- Multi-sitio e autenticação do dashboard
- Retenção de dados e exportação (CSV/JSON)
- Geo/localização

## Licença

MIT — veja [MIT-LICENSE](MIT-LICENSE).