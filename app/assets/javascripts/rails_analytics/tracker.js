// Rails Analytics — Cookie-less tracker (~3 KB)
// No cookies, no localStorage, no fingerprinting. LGPD-compliant by design.

(function () {
  "use strict";

  var FLUSH_INTERVAL = 10000; // 10s
  var MAX_BATCH = 20;

  // Reads the endpoint from the script tag (helper injects data-endpoint)
  var script = document.currentScript || document.querySelector("script[data-rails-analytics]");
  var ENDPOINT = (script && script.getAttribute("data-endpoint")) || "/rails_analytics";

  var queue = [];
  var token = null;

  function randomHex(len) {
    var arr = new Uint8Array(len);
    crypto.getRandomValues(arr);
    return Array.from(arr, function (b) { return b.toString(16).padStart(2, "0"); }).join("");
  }

  var nonce = randomHex(16);

  function deviceType() {
    var w = screen.width || window.innerWidth || 0;
    if (w >= 1024) return "desktop";
    if (w >= 768) return "tablet";
    return "mobile";
  }

  function referrerDomain() {
    try {
      var ref = document.referrer;
      if (!ref) return "direct";
      var u = new URL(ref);
      return u.hostname;
    } catch (e) {
      return "direct";
    }
  }

  function payload() {
    return {
      path: location.pathname + location.search,
      referrer_domain: referrerDomain(),
      device_type: deviceType(),
      viewport: screen.width + "x" + screen.height,
      language: (navigator.language || "").slice(0, 10),
      nonce: nonce,
      events: queue
    };
  }

  function fetchToken() {
    return fetch(ENDPOINT + "/token", { credentials: "same-origin" })
      .then(function (r) { return r.json(); })
      .then(function (data) { token = data.token; })
      .catch(function () { /* silently fail */ });
  }

  function flush() {
    if (queue.length === 0 || !token) return;

    var batch = queue.splice(0, MAX_BATCH);
    var body = payload();
    body.events = batch;

    // sendBeacon does not allow custom headers — token goes in the body.
    if (navigator.sendBeacon) {
      body.token = token;
      navigator.sendBeacon(ENDPOINT + "/collect", new Blob([JSON.stringify(body)], { type: "application/json" }));
    } else {
      fetch(ENDPOINT + "/collect", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer " + token
        },
        body: JSON.stringify(body),
        keepalive: true
      }).catch(function () {});
    }

    nonce = randomHex(16); // rotate nonce after each batch
  }

  function track(name, properties) {
    queue.push({
      name: name,
      time: new Date().toISOString(),
      properties: properties || {}
    });
    if (queue.length >= MAX_BATCH) flush();
  }

  function scheduleFlush() {
    fetchToken().then(function () {
      flush(); // send initial pageview as event
      setInterval(flush, FLUSH_INTERVAL);
    });
  }

  // Send on page exit (survives tab close)
  function onPageHide() {
    if (queue.length > 0 && token) {
      var body = payload();
      body.token = token;
      if (navigator.sendBeacon) {
        navigator.sendBeacon(ENDPOINT + "/collect", new Blob([JSON.stringify(body)], { type: "application/json" }));
      } else {
        fetch(ENDPOINT + "/collect", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": "Bearer " + token },
          body: JSON.stringify(body),
          keepalive: true
        }).catch(function () {});
      }
      queue = [];
    }
  }

  // Expose public API
  window.RailsAnalytics = { track: track };

  // Init
  if (document.readyState === "complete") {
    scheduleFlush();
  } else {
    window.addEventListener("load", scheduleFlush);
  }
  window.addEventListener("pagehide", onPageHide);
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden") onPageHide();
  });
})();