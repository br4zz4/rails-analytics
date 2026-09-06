# frozen_string_literal: true

require "test_helper"

class RailsAnalytics::PixelTest < ActionDispatch::IntegrationTest
  def setup
    RailsAnalytics::PageView.delete_all
  end

  test "px.gif grava uma page view e responde imagem gif" do
    assert_difference -> { RailsAnalytics::PageView.count }, 1 do
      get "/rails_analytics/px.gif",
          params: { sid: "abc123", path: "/blog/hello", referrer: "https://google.com",
                    title: "Hello", sw: 1440, sh: 900, lang: "pt-BR" },
          headers: { "User-Agent" => "Mozilla/5.0 (Macintosh)" }
    end

    assert_response :success
    assert_equal "image/gif", response.media_type

    row = RailsAnalytics::PageView.last
    assert_equal "/blog/hello", row.path
    assert_equal "https://google.com", row.referrer
    assert_equal "Hello", row.title
    assert_equal 1440, row.screen_width
    assert_equal 900, row.screen_height
    assert_equal "pt-BR", row.language
    assert_equal "Mozilla/5.0 (Macintosh)", row.user_agent
    assert_equal "abc123", row.session_id
    assert row.ip_hash.present?
    assert_not_equal "127.0.0.1", row.ip_hash, "IP não pode ser guardado cru"
    assert row.viewed_at.present?
  end

  test "px.gif sem path retorna 400 e não grava" do
    assert_no_difference -> { RailsAnalytics::PageView.count } do
      get "/rails_analytics/px.gif", params: { sid: "x1" }
    end

    assert_response :bad_request
  end

  test "path com mais de 500 chars é truncado" do
    get "/rails_analytics/px.gif",
        params: { sid: "s", path: "p" * 700 }

    assert_response :success
    assert_equal 500, RailsAnalytics::PageView.last.path.length
  end
end

class RailsAnalytics::TrackerTest < ActionDispatch::IntegrationTest
  test "tracker.js é servido como javascript" do
    get "/rails_analytics/tracker.js"

    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert_includes response.body, "rails_analytics.sid"
    assert_includes response.body, "px.gif"
  end

  test "dashboard.css é servido como css" do
    get "/rails_analytics/dashboard.css"

    assert_response :success
    assert_equal "text/css", response.media_type
    assert_includes response.body, "--ra-accent"
  end
end

class RailsAnalytics::DashboardTest < ActionDispatch::IntegrationTest
  def setup
    RailsAnalytics::PageView.delete_all
    seed_views
  end

  def seed_views
    now = Time.current
    [
      ["/",        "/", "Home",   1440, 900, "pt-BR", "s1", now],
      ["/blog",    "/", "Blog",   1440, 900, "pt-BR", "s1", now],
      ["/blog",    "/", "Blog",    390,  844, "pt-BR", "s2", 1.day.ago],
      ["/contato", "/blog", "Contato", 390, 844, "en", "s2", 2.days.ago]
    ].each do |path, ref, title, sw, sh, lang, sid, viewed_at|
      RailsAnalytics::PageView.create!(
        path: path, referrer: ref, title: title,
        screen_width: sw, screen_height: sh, language: lang,
        user_agent: "Mozilla/5.0", ip_hash: "h", session_id: sid,
        viewed_at: viewed_at
      )
    end
  end

  test "dashboard renderiza KPIs e séries" do
    get "/rails_analytics/"

    assert_response :success
    assert_includes response.body, "Visitas hoje"
    assert_includes response.body, "Visitantes únicos"
    assert_includes response.body, "/blog"
    assert_includes response.body, "Desktop"
    assert_includes response.body, "svg"
  end
end