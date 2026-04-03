/**
 * API Configuration
 *
 * This file is auto-updated by the VM when the tunnel URL changes.
 * The VM script parses the new tunnel URL and pushes an update to this file.
 *
 * To update: change the URL below and git push, or let the VM script handle it.
 */
(function () {
  window.NEWS_API_BASE = 'https://repository-substantially-hockey-algebra.trycloudflare.com';

  // --- Retry/reconnect logic ---
  var MAX_RETRIES = 5;
  var RETRY_INTERVAL = 5000; // 5 seconds between retries
  var CONFIG_URL = 'https://raw.githubusercontent.com/jchrislee16/News-Paper-Scraper/main/js/config.js';

  var overlay = null;

  function showReconnecting() {
    if (overlay) return;
    overlay = document.createElement('div');
    overlay.id = 'api-reconnect-overlay';
    overlay.innerHTML =
      '<div style="text-align:center;">' +
        '<i class="fa fa-spinner fa-spin fa-3x" style="color:#ffbe33;"></i>' +
        '<p style="margin-top:15px;font-size:16px;color:#333;">Reconnecting to server...</p>' +
        '<p style="font-size:13px;color:#888;">This usually takes a few seconds</p>' +
      '</div>';
    overlay.style.cssText =
      'position:fixed;top:0;left:0;width:100%;height:100%;' +
      'background:rgba(255,255,255,0.95);display:flex;align-items:center;' +
      'justify-content:center;z-index:99999;';
    document.body.appendChild(overlay);
  }

  function hideReconnecting() {
    if (overlay) {
      overlay.remove();
      overlay = null;
    }
  }

  // Fetch the latest config.js from GitHub raw to check for a new URL
  function fetchLatestUrl(callback) {
    fetch(CONFIG_URL + '?t=' + Date.now())
      .then(function (res) { return res.text(); })
      .then(function (text) {
        var match = text.match(/window\.NEWS_API_BASE\s*=\s*['"]([^'"]+)['"]/);
        if (match && match[1]) {
          window.NEWS_API_BASE = match[1];
        }
        callback(window.NEWS_API_BASE);
      })
      .catch(function () {
        callback(window.NEWS_API_BASE);
      });
  }

  // Wrapped fetch that retries and shows reconnecting overlay on failure
  window.apiFetch = function (path, options) {
    var retries = 0;

    function attempt() {
      return fetch(window.NEWS_API_BASE + path, options)
        .then(function (res) {
          if (!res.ok) throw new Error('API returned ' + res.status);
          hideReconnecting();
          return res;
        })
        .catch(function (err) {
          retries++;
          if (retries > MAX_RETRIES) {
            hideReconnecting();
            throw err;
          }
          showReconnecting();
          // Re-fetch config to see if URL changed, then retry
          return new Promise(function (resolve) {
            setTimeout(function () {
              fetchLatestUrl(function () {
                resolve(attempt());
              });
            }, RETRY_INTERVAL);
          });
        });
    }

    return attempt();
  };
})();
