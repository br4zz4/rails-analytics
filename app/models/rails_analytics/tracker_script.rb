# frozen_string_literal: true

module RailsAnalytics
  # Código-fonte do tracker JS servido pelo engine (sem depender do asset pipeline).
  module TrackerScript
    SOURCE = <<~JS
      (function () {
        "use strict";
        var KEY = "rails_analytics.sid";
        var sid = localStorage.getItem(KEY);
        if (!sid) {
          sid = Math.random().toString(36).slice(2) + Date.now().toString(36);
          localStorage.setItem(KEY, sid);
        }
        function track() {
          var el = document.querySelector("script[data-rails-analytics]");
          if (!el) return;
          var base = el.getAttribute("data-endpoint") || "/rails_analytics";
          var params = [
            "sid=" + encodeURIComponent(sid),
            "path=" + encodeURIComponent(location.pathname + location.search),
            "referrer=" + encodeURIComponent(document.referrer),
            "title=" + encodeURIComponent(document.title),
            "sw=" + (screen.width || 0),
            "sh=" + (screen.height || 0),
            "lang=" + encodeURIComponent((navigator.language || "").slice(0, 8))
          ];
          var img = new Image();
          img.src = base + "/px.gif?" + params.join("&");
        }
        if (document.readyState === "complete") { track(); }
        else { window.addEventListener("load", track); }
      })();
    JS

    def self.source
      SOURCE
    end
  end
end