/**
 * Merged ranker — the single sorting mechanism for the feed.
 *
 * Replaces the old two-pass system (server ranks -> user-prefs.js re-sorts the
 * DOM on different criteria). Both signals are now folded into ONE score, and
 * the feed is rendered in that order once. Nothing re-sorts afterwards.
 *
 * The two signals being merged:
 *   SERVER  article.rank_score from POST /api/recommend — cosine similarity to
 *           the TF-IDF "soup" built from the titles the user clicked. This is
 *           the content signal: what the article is actually about.
 *   CLIENT  0.7 x topicScore + 0.3 x sourceScore from localStorage newsUserPrefs.
 *           The habit signal: which feeds/categories the user keeps returning to.
 *
 * WHY NORMALIZE: the two are not on the same scale and must never be added raw.
 * Measured live against the API:
 *     rank_score with clicks : 0.143 - 0.196   (spread 0.053)
 *     rank_score cold start  : 0.567 - 0.599   (spread 0.031)
 *     client blend           : 0 - ~0.4        (spread ~0.4)
 * The server's whole discriminating range is ~0.05 wide AND its absolute
 * position shifts depending on whether the user has clicks, so a raw
 * 0.5*server + 0.5*client would let the client score bulldoze it every time.
 * Both sides are therefore min-max normalized to 0-1 ACROSS THE RETURNED LIST
 * before blending, which makes them comparable and mode-independent.
 */
(function () {
  // --- Blend weights (must sum to 1) ---
  // Server is weighted higher because it reads article TEXT. The client signal
  // is topic+source, and category is ~91% predictable from source alone, so it
  // is closer to one signal than two — see CLAUDE.md "Category is just source".
  var SERVER_WEIGHT = 0.6;
  var CLIENT_WEIGHT = 0.4;

  // Already-read articles sink below every unread one. This has to be a
  // penalty bigger than the entire score range, not a small "unread boost":
  // `blended` maxes out at 1.0, so the old +0.5 unread boost let an article
  // that topped BOTH signals outrank every unread card and hold slot #1 even
  // after you had read it (observed against live data). At 3.0 the read band
  // is [-3,-2] and the unread band is [0,1] even after the worst-case
  // diversity penalty (3 x 0.4 = 1.2), so the two can never interleave.
  var READ_PENALTY = 3.0;
  var PENALTY = 0.4;        // per repeat of a topic in the recent window
  var LOOKBACK = 3;         // how many recent slots count as "recent"

  // The client half stays off until there is enough history to mean anything.
  var MIN_CLICKS = 3;

  // Same 70/30 split the old client pass used.
  var TOPIC_WEIGHT = 0.7;
  var SOURCE_WEIGHT = 0.3;

  // Prefer the shared helpers from user-prefs.js so TOPIC_MAP has one home.
  // Falls back to a local implementation if this file is used standalone.
  function prefsApi() {
    return window.NewsPrefs || null;
  }

  function loadPrefs() {
    var api = prefsApi();
    if (api) return api.loadPrefs();
    try {
      var raw = JSON.parse(localStorage.getItem('newsUserPrefs') || '{}');
      raw.readArticles = raw.readArticles || [];
      raw.topicScores = raw.topicScores || {};
      raw.sourceScores = raw.sourceScores || {};
      return raw;
    } catch (e) {
      return { readArticles: [], topicScores: {}, sourceScores: {} };
    }
  }

  function normalizeTopic(displayName) {
    var api = prefsApi();
    if (api) return api.normalizeTopic(displayName);
    if (!displayName) return null;
    var d = displayName.toLowerCase();
    return (d === 'technology') ? 'tech' : d;
  }

  // Build a min-max normalizer over a set of raw values. Maps the lowest value
  // in the list to 0 and the highest to 1. If every value is identical (or the
  // signal is unavailable) the whole signal collapses to 0 and contributes
  // nothing, which is the correct behaviour for an absent signal.
  function normalizer(values) {
    var min = Infinity;
    var max = -Infinity;
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      if (typeof v !== 'number' || !isFinite(v)) continue;
      if (v < min) min = v;
      if (v > max) max = v;
    }
    var range = max - min;
    if (!isFinite(range) || range <= 0) {
      return function () { return 0; };
    }
    return function (v) {
      if (typeof v !== 'number' || !isFinite(v)) return 0;
      return (v - min) / range;
    };
  }

  // The server's relevance number. `rank_score` is the cosine similarity added
  // by /api/recommend; `score` is a popularity field that is 0 for most
  // articles, so it is NOT a usable ranking signal and is only a last resort.
  // With neither, fall back to the order the server sent (first = best).
  function serverSignal(article, index, total) {
    if (typeof article.rank_score === 'number') return article.rank_score;
    if (typeof article.score === 'number' && article.score > 0) return article.score;
    return (total - index) / total;
  }

  function clientSignal(article, prefs) {
    var topic = normalizeTopic(article.category);
    var topicScore = (topic && prefs.topicScores[topic]) || 0;
    var sourceScore = (article.source && prefs.sourceScores[article.source]) || 0;
    return {
      topic: topic,
      topicScore: topicScore,
      sourceScore: sourceScore,
      raw: (TOPIC_WEIGHT * topicScore) + (SOURCE_WEIGHT * sourceScore)
    };
  }

  /**
   * Rank articles by the merged score.
   * @param {Array} articles - articles as returned by /api/recommend
   * @returns {Array} new array, sorted, each article carrying a `_rank` breakdown
   */
  function getRecommendedNews(articles) {
    if (!articles || !articles.length) return [];

    var prefs = loadPrefs();
    var readArticles = prefs.readArticles || [];
    var total = articles.length;

    // The client half only earns its weight once there is real history behind
    // it. Below that, the server takes the full 1.0 and the feed is pure
    // content matching rather than habit reinforcement.
    var hasHistory =
      readArticles.length >= MIN_CLICKS &&
      (Object.keys(prefs.topicScores).length > 0 || Object.keys(prefs.sourceScores).length > 0);
    var clientWeight = hasHistory ? CLIENT_WEIGHT : 0;
    var serverWeight = 1 - clientWeight;

    var rows = articles.map(function (article, i) {
      var client = clientSignal(article, prefs);
      return {
        article: article,
        topic: client.topic,
        serverRaw: serverSignal(article, i, total),
        clientRaw: client.raw,
        topicScore: client.topicScore,
        sourceScore: client.sourceScore,
        unread: readArticles.indexOf(article.url) === -1
      };
    });

    var normServer = normalizer(rows.map(function (r) { return r.serverRaw; }));
    var normClient = normalizer(rows.map(function (r) { return r.clientRaw; }));

    rows.forEach(function (r) {
      r.serverNorm = normServer(r.serverRaw);
      r.clientNorm = normClient(r.clientRaw);
      r.blended = (serverWeight * r.serverNorm) + (clientWeight * r.clientNorm);
      r.penalty = r.unread ? 0 : READ_PENALTY;
      r.score = r.blended - r.penalty;
    });

    // Diversified placement (MMR-style), carried over from the old client pass:
    // repeatedly take the best remaining article, but subtract PENALTY for each
    // time its topic already appeared in the last LOOKBACK slots. The favourite
    // topic still wins the most slots, it just gets spread through the feed
    // instead of stacked 30-in-a-row. This runs even with no click history,
    // because cold-start server order clumps hard by category on its own.
    var ordered = [];
    var recentTopics = [];

    while (rows.length) {
      var bestIdx = 0;
      var bestVal = -Infinity;
      for (var i = 0; i < rows.length; i++) {
        var repeats = 0;
        for (var r = 0; r < recentTopics.length; r++) {
          if (recentTopics[r] === rows[i].topic) repeats++;
        }
        var adjusted = rows[i].score - (repeats * PENALTY);
        if (adjusted > bestVal) {
          bestVal = adjusted;
          bestIdx = i;
        }
      }

      var picked = rows.splice(bestIdx, 1)[0];
      picked.adjusted = bestVal;
      picked.slot = ordered.length + 1;
      recentTopics.push(picked.topic);
      if (recentTopics.length > LOOKBACK) recentTopics.shift();
      ordered.push(picked);
    }

    // Attach the arithmetic to each article so the debug badge can explain the
    // placement without recomputing any of it.
    return ordered.map(function (r) {
      r.article._rank = {
        slot: r.slot,
        topic: r.topic,
        serverRaw: r.serverRaw,
        serverNorm: r.serverNorm,
        serverWeight: serverWeight,
        clientRaw: r.clientRaw,
        clientNorm: r.clientNorm,
        clientWeight: clientWeight,
        topicScore: r.topicScore,
        sourceScore: r.sourceScore,
        blended: r.blended,
        unread: r.unread,
        readPenalty: r.penalty,
        score: r.score,
        adjusted: r.adjusted,
        hasHistory: hasHistory
      };
      return r.article;
    });
  }

  window.getRecommendedNews = getRecommendedNews;
  window.RANK_WEIGHTS = {
    SERVER_WEIGHT: SERVER_WEIGHT,
    CLIENT_WEIGHT: CLIENT_WEIGHT,
    READ_PENALTY: READ_PENALTY,
    PENALTY: PENALTY,
    LOOKBACK: LOOKBACK,
    MIN_CLICKS: MIN_CLICKS
  };
})();
