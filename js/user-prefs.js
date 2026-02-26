/**
 * User Preferences via localStorage
 *
 * Learns what each user likes based on their reading history (categories & sources),
 * then reorders articles to show their preferred content first.
 * All data lives in localStorage — nothing is sent to the server.
 *
 * Topic keys match the DB `topics` table from trend.sql:
 *   tech, economy, politics, health, sports, entertainment, science
 *
 * Stored data shape:
 * {
 *   readArticles: ["url1", "url2", ...],
 *   savedArticles: ["url1", "url2", ...],
 *   topicScores: { "tech": 5, "politics": 2, ... },
 *   sourceScores: { "Washington Post": 8, "BBC": 3, ... }
 * }
 */
(function () {
  var STORAGE_KEY = 'newsUserPrefs';

  // Maps display names (from HTML badges & data-category attrs) → DB topic keys.
  // Keeps localStorage aligned with the `topics` table in trend.sql.
  var TOPIC_MAP = {
    'Technology': 'tech',
    'Tech':       'tech',
    'Politics':   'politics',
    'World':      'politics',    // closest DB topic
    'Business':   'economy',
    'Economy':    'economy',
    'Science':    'science',
    'Health':     'health',
    'Sports':     'sports',
    'Entertainment': 'entertainment',
    'General':    'tech'         // fallback for uncategorized
  };

  // Reverse map: DB topic key → nice display name for the UI
  var TOPIC_DISPLAY = {
    'tech':          'Technology',
    'economy':       'Economy',
    'politics':      'Politics',
    'health':        'Health',
    'sports':        'Sports',
    'entertainment': 'Entertainment',
    'science':       'Science'
  };

  function normalizeTopic(displayName) {
    if (!displayName) return null;
    return TOPIC_MAP[displayName] || displayName.toLowerCase();
  }

  function topicDisplayName(key) {
    return TOPIC_DISPLAY[key] || key;
  }

  // --- localStorage helpers ---

  function loadPrefs() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        var prefs = JSON.parse(raw);
        // ensure all fields exist (migration-safe)
        prefs.readArticles = prefs.readArticles || [];
        prefs.savedArticles = prefs.savedArticles || [];
        prefs.sourceScores = prefs.sourceScores || {};
        // migrate old categoryScores → topicScores if needed
        if (prefs.categoryScores && !prefs.topicScores) {
          prefs.topicScores = {};
          for (var cat in prefs.categoryScores) {
            var key = normalizeTopic(cat);
            prefs.topicScores[key] = (prefs.topicScores[key] || 0) + prefs.categoryScores[cat];
          }
          delete prefs.categoryScores;
          savePrefs(prefs);
        }
        prefs.topicScores = prefs.topicScores || {};
        return prefs;
      }
    } catch (e) {
      console.debug('Failed to load prefs:', e);
    }
    return { readArticles: [], savedArticles: [], topicScores: {}, sourceScores: {} };
  }

  function savePrefs(prefs) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
    } catch (e) {
      console.debug('Failed to save prefs:', e);
    }
  }

  // --- Preference tracking ---

  function recordClick(url, category, source) {
    var prefs = loadPrefs();

    // track the article as read
    if (prefs.readArticles.indexOf(url) === -1) {
      prefs.readArticles.push(url);
    }

    // bump topic score (normalized to DB key)
    var topic = normalizeTopic(category);
    if (topic) {
      prefs.topicScores[topic] = (prefs.topicScores[topic] || 0) + 1;
    }

    // bump source score
    if (source) {
      prefs.sourceScores[source] = (prefs.sourceScores[source] || 0) + 1;
    }

    savePrefs(prefs);
  }

  function isRead(url) {
    return loadPrefs().readArticles.indexOf(url) !== -1;
  }

  function toggleSave(url) {
    var prefs = loadPrefs();
    var idx = prefs.savedArticles.indexOf(url);
    if (idx === -1) {
      prefs.savedArticles.push(url);
    } else {
      prefs.savedArticles.splice(idx, 1);
    }
    savePrefs(prefs);
    return idx === -1;
  }

  function isSaved(url) {
    return loadPrefs().savedArticles.indexOf(url) !== -1;
  }

  // Get the user's top topic key (the one they click most)
  function getTopTopic() {
    var scores = loadPrefs().topicScores;
    var top = null;
    var topScore = 0;
    for (var topic in scores) {
      if (scores[topic] > topScore) {
        topScore = scores[topic];
        top = topic;
      }
    }
    return top;
  }

  // Calculate a preference score for a card based on the user's history
  function getPreferenceScore(category, source) {
    var prefs = loadPrefs();
    var score = 0;
    var topic = normalizeTopic(category);
    if (topic && prefs.topicScores[topic]) {
      score += prefs.topicScores[topic];
    }
    if (source && prefs.sourceScores[source]) {
      score += prefs.sourceScores[source];
    }
    return score;
  }

  // --- DOM helpers ---

  function getArticleUrl(card) {
    var link = card.querySelector('a.btn, a.track-click');
    return link ? link.href : null;
  }

  function getArticleCategory(card) {
    // try data-category on the link first (trend_2.html uses this)
    var link = card.querySelector('a.track-click');
    if (link && link.dataset.category && link.dataset.category !== 'Unknown') {
      return link.dataset.category;
    }
    // fall back to the badge text
    var badge = card.querySelector('.badge');
    return badge ? badge.textContent.trim() : null;
  }

  function getArticleSource(card) {
    // try data-source on the link
    var link = card.querySelector('a.track-click');
    if (link && link.dataset.source && link.dataset.source !== 'Unknown') {
      return link.dataset.source;
    }
    // default for trend.html (all Washington Post)
    return 'Washington Post';
  }

  function getAllCards() {
    var container = document.getElementById('tech-news-container');
    if (!container) return [];
    return Array.prototype.slice.call(container.querySelectorAll('.col-md-6'));
  }

  // --- Sort articles by user preference ---

  function sortByPreference() {
    var container = document.getElementById('tech-news-container');
    if (!container) return;

    var prefs = loadPrefs();
    var totalClicks = prefs.readArticles.length;

    // only sort if the user has clicked at least 3 articles (enough signal)
    if (totalClicks < 3) return;

    var cards = getAllCards();
    if (cards.length === 0) return;

    // score each card
    var scored = cards.map(function (card) {
      var category = getArticleCategory(card);
      var source = getArticleSource(card);
      var score = getPreferenceScore(category, source);
      // unread articles get a slight boost so you see new stuff first
      var url = getArticleUrl(card);
      if (url && !isRead(url)) score += 0.5;
      return { card: card, score: score };
    });

    // sort descending by score (stable: preserve original order for ties)
    scored.sort(function (a, b) { return b.score - a.score; });

    // reorder DOM
    scored.forEach(function (item) {
      container.appendChild(item.card);
    });
  }

  // --- Inject filter toolbar + preference summary ---

  function createFilterBar() {
    var container = document.getElementById('tech-news-container');
    if (!container) return;

    var prefs = loadPrefs();
    var topTopic = getTopTopic();

    var bar = document.createElement('div');
    bar.id = 'prefs-filter-bar';
    bar.style.cssText = 'width:100%;margin-bottom:20px;padding:12px 16px;background:#f8f9fa;border-radius:8px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;justify-content:space-between;';

    // left side: filter buttons
    var leftSide = '<div style="display:flex;gap:8px;align-items:center;">' +
      '<span style="font-weight:bold;margin-right:4px;color:#333;">Filter:</span>' +
      '<button class="prefs-filter-btn" data-filter="all" style="' + btnBaseStyle() + btnActiveStyle() + '">All</button>' +
      '<button class="prefs-filter-btn" data-filter="unread" style="' + btnBaseStyle() + '">Unread</button>' +
      '<button class="prefs-filter-btn" data-filter="saved" style="' + btnBaseStyle() + '">Saved</button>' +
      '</div>';

    // right side: preference summary (only show if they have history)
    var rightSide = '';
    if (topTopic) {
      rightSide = '<div style="font-size:13px;color:#666;">' +
        '<i class="fa fa-heart" style="color:#dc3545;margin-right:4px;"></i>' +
        'Your top interest: <strong style="color:#333;">' + topicDisplayName(topTopic) + '</strong>' +
        ' <span style="color:#999;">(' + prefs.readArticles.length + ' articles read)</span>' +
        '</div>';
    } else {
      rightSide = '<div style="font-size:13px;color:#999;">' +
        '<i class="fa fa-info-circle" style="margin-right:4px;"></i>' +
        'Read articles to build your personalized trend' +
        '</div>';
    }

    bar.innerHTML = leftSide + rightSide;
    container.parentNode.insertBefore(bar, container);

    // attach filter handlers
    var buttons = bar.querySelectorAll('.prefs-filter-btn');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener('click', function () {
        for (var j = 0; j < buttons.length; j++) {
          buttons[j].style.backgroundColor = '#e9ecef';
          buttons[j].style.color = '#333';
          buttons[j].style.fontWeight = 'normal';
        }
        this.style.backgroundColor = '#222';
        this.style.color = '#fff';
        this.style.fontWeight = 'bold';
        applyFilter(this.dataset.filter);
      });
    }
  }

  function btnBaseStyle() {
    return 'border:none;padding:6px 16px;border-radius:4px;cursor:pointer;font-size:13px;background:#e9ecef;color:#333;transition:all 0.2s;';
  }

  function btnActiveStyle() {
    return 'background-color:#222;color:#fff;font-weight:bold;';
  }

  // --- Apply filter ---

  function applyFilter(filter) {
    var cards = getAllCards();
    cards.forEach(function (card) {
      var url = getArticleUrl(card);
      if (!url) return;

      var show = true;
      if (filter === 'unread') show = !isRead(url);
      if (filter === 'saved') show = isSaved(url);

      card.style.display = show ? '' : 'none';
    });
  }

  // --- Decorate cards with bookmark, read status, and "For You" badge ---

  function decorateCards() {
    var cards = getAllCards();
    var prefs = loadPrefs();
    var topTopic = getTopTopic();

    cards.forEach(function (card) {
      var url = getArticleUrl(card);
      if (!url) return;
      var cardBody = card.querySelector('.card-body');
      if (!cardBody) return;

      if (card.dataset.prefsDecorated) return;
      card.dataset.prefsDecorated = 'true';

      var category = getArticleCategory(card);
      var source = getArticleSource(card);

      // --- Card positioning for overlay elements ---
      var cardEl = card.querySelector('.card');
      if (cardEl) cardEl.style.position = 'relative';

      // --- Bookmark button (top-right) ---
      var bookmarkBtn = document.createElement('button');
      bookmarkBtn.title = 'Bookmark this article';
      bookmarkBtn.style.cssText =
        'position:absolute;top:10px;right:10px;background:none;border:none;cursor:pointer;font-size:20px;z-index:2;padding:4px;opacity:0.7;transition:opacity 0.2s;';
      bookmarkBtn.innerHTML = isSaved(url)
        ? '<i class="fa fa-bookmark" style="color:#ffbe33;"></i>'
        : '<i class="fa fa-bookmark-o" style="color:#999;"></i>';

      bookmarkBtn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var nowSaved = toggleSave(url);
        this.innerHTML = nowSaved
          ? '<i class="fa fa-bookmark" style="color:#ffbe33;"></i>'
          : '<i class="fa fa-bookmark-o" style="color:#999;"></i>';
      });

      if (cardEl) cardEl.appendChild(bookmarkBtn);

      // --- "For You" badge if topic matches user's top interest ---
      var cardTopic = normalizeTopic(category);
      if (topTopic && cardTopic === topTopic && !isRead(url)) {
        var forYouBadge = document.createElement('span');
        forYouBadge.className = 'prefs-foryou-badge';
        forYouBadge.style.cssText =
          'display:inline-block;background:#dc3545;color:#fff;padding:2px 8px;border-radius:4px;font-size:11px;margin-left:6px;vertical-align:middle;';
        forYouBadge.innerHTML = '<i class="fa fa-heart" style="margin-right:3px;"></i>For You';
        var existingBadge = cardBody.querySelector('.badge');
        if (existingBadge) {
          existingBadge.parentNode.insertBefore(forYouBadge, existingBadge.nextSibling);
        }
      }

      // --- Track click on "Read More" ---
      var readMoreLink = card.querySelector('a.btn, a.track-click');
      if (readMoreLink) {
        readMoreLink.addEventListener('click', function () {
          recordClick(url, category, source);
          applyReadStyling(card, true);
        });
      }

      // --- Apply read styling if already read ---
      if (isRead(url)) {
        applyReadStyling(card, true);
      }
    });
  }

  function applyReadStyling(card, read) {
    var cardEl = card.querySelector('.card');
    if (!cardEl) return;

    if (read) {
      cardEl.style.opacity = '0.6';
      var cardBody = card.querySelector('.card-body');
      if (cardBody && !cardBody.querySelector('.prefs-read-badge')) {
        var badge = document.createElement('span');
        badge.className = 'prefs-read-badge';
        badge.style.cssText =
          'display:inline-block;background:#6c757d;color:#fff;padding:2px 8px;border-radius:4px;font-size:11px;margin-left:6px;vertical-align:middle;';
        badge.textContent = 'Read';
        var existingBadge = cardBody.querySelector('.badge');
        if (existingBadge) {
          existingBadge.parentNode.insertBefore(badge, existingBadge.nextSibling);
        }
      }
    }
  }

  // --- Initialize ---

  function init() {
    createFilterBar();
    sortByPreference();
    decorateCards();

    var prefs = loadPrefs();
    console.debug('User prefs initialized.',
      'Read:', prefs.readArticles.length,
      'Saved:', prefs.savedArticles.length,
      'Topic scores:', prefs.topicScores,
      'Source scores:', prefs.sourceScores);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
