/**
 * News Feed Loader
 * Fetches personalized articles from the backend API based on localStorage preferences.
 * Renders article cards into #tech-news-container.
 */
(function () {
  var STORAGE_KEY = 'newsUserPrefs';
  var ARTICLES_CACHE_KEY = 'cachedArticles';

  var CATEGORY_COLORS = {
    'Technology': '#007bff',
    'Politics': '#dc3545',
    'World': '#28a745',
    'Business': '#fd7e14',
    'Science': '#6f42c1',
    'Entertainment': '#e83e8c',
    'Sports': '#20c997',
    'General': '#6c757d'
  };

  var RANK_COLORS = ['#ff4444', '#ff8800', '#ffbb00'];

  function loadPrefs() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    return { readArticles: [], savedArticles: [], topicScores: {}, sourceScores: {} };
  }

  function renderCard(article, rank) {
    var rankColor = rank < 3 ? RANK_COLORS[rank] : '#6c757d';
    var catColor = CATEGORY_COLORS[article.category] || '#6c757d';
    var title = article.title || 'No Title';
    var summary = article.summary || '';
    var source = article.source || 'Unknown';
    var published = '';
    if (article.published) {
      try {
        var d = new Date(article.published);
        published = d.toLocaleDateString('en-US', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });
      } catch (e) {
        published = article.published;
      }
    }
    var scoreText = article.score > 0 ? "<small style='color: #28a745;'>Score: " + article.score.toLocaleString() + "</small>" : '';

    // Escape HTML in title for data attributes
    var safeTitle = title.replace(/"/g, '&quot;').replace(/'/g, '&#39;');

    return '<div class="col-md-6 col-lg-4 mb-4">' +
      '<div class="card h-100" style="border: 1px solid #ddd; border-radius: 8px; overflow: hidden;">' +
        '<div class="card-body">' +
          '<span class="badge" style="background-color: ' + rankColor + '; color: #fff; padding: 3px 8px; border-radius: 50%; font-size: 11px; margin-right: 5px;">#' + (rank + 1) + '</span>' +
          '<span class="badge" style="background-color: #ffbe33; color: #fff; padding: 5px 10px; border-radius: 4px; font-size: 12px;">' + source + '</span>' +
          '<span class="badge" style="background-color: ' + catColor + '; color: #fff; padding: 5px 10px; border-radius: 4px; font-size: 12px; margin-left: 5px;">' + (article.category || 'General') + '</span>' +
          '<h5 class="card-title mt-2" style="font-weight: bold; color: #222;">' + title + '</h5>' +
          '<p class="card-text" style="color: #666; font-size: 14px;">' + summary + '</p>' +
          '<p style="color: #999; font-size: 12px;"><i class="fa fa-calendar"></i> ' + published + ' ' + scoreText + '</p>' +
          '<a href="' + article.url + '" target="_blank" class="btn track-click" ' +
            'style="background-color: #222; color: #fff; padding: 8px 16px; border-radius: 4px; font-size: 14px;" ' +
            'data-title="' + safeTitle + '" data-source="' + source + '" data-category="' + article.category + '">' +
            'Read More</a>' +
        '</div>' +
      '</div>' +
    '</div>';
  }

  function renderCategorySection(category, articles) {
    var color = CATEGORY_COLORS[category] || '#6c757d';
    var html = '<div class="category-section mb-5">' +
      '<h3 style="color: ' + color + '; border-bottom: 3px solid ' + color + '; padding-bottom: 10px; margin-bottom: 20px;">' +
        '<i class="fa fa-fire" style="margin-right: 8px;"></i>' + category +
      '</h3>' +
      '<div class="row">';

    articles.forEach(function (article, i) {
      html += renderCard(article, i);
    });

    html += '</div></div>';
    return html;
  }

  function renderArticles(data) {
    var container = document.getElementById('tech-news-container');
    if (!container) return;

    var articles = data.articles || [];
    if (articles.length === 0) {
      container.innerHTML = '<div style="text-align:center;padding:40px;"><p style="color:#666;">No articles available. Please check back later.</p></div>';
      return;
    }

    // Group by category
    var grouped = {};
    articles.forEach(function (a) {
      var cat = a.category || 'General';
      if (!grouped[cat]) grouped[cat] = [];
      grouped[cat].push(a);
    });

    // Render in category order from API
    var categories = data.categories || Object.keys(grouped);
    var html = '';
    categories.forEach(function (cat) {
      if (grouped[cat] && grouped[cat].length > 0) {
        html += renderCategorySection(cat, grouped[cat]);
      }
    });

    container.innerHTML = html;

    // Cache for offline use
    try {
      localStorage.setItem(ARTICLES_CACHE_KEY, JSON.stringify(data));
    } catch (e) {}

    // Re-init click tracking for dynamically rendered cards
    if (typeof window.reinitClickTracking === 'function') {
      setTimeout(window.reinitClickTracking, 50);
    }

    // Re-init user prefs (bookmarks, read status, For You badges)
    if (typeof window.reinitUserPrefs === 'function') {
      setTimeout(window.reinitUserPrefs, 100);
    }
  }

  function showLoading(container) {
    container.innerHTML =
      '<div style="width:100%;text-align:center;padding:40px;">' +
        '<i class="fa fa-spinner fa-spin fa-3x" style="color:#ffbe33;"></i>' +
        '<p style="margin-top:10px;color:#666;">Loading personalized news...</p>' +
      '</div>';
  }

  function showError(container, message) {
    container.innerHTML =
      '<div style="width:100%;text-align:center;padding:40px;">' +
        '<i class="fa fa-exclamation-triangle fa-3x" style="color:#dc3545;"></i>' +
        '<p style="margin-top:10px;color:#666;">' + message + '</p>' +
        '<button id="retry-btn" class="btn" style="background-color:#222;color:#fff;padding:8px 20px;border-radius:4px;">Retry</button>' +
      '</div>';
    document.getElementById('retry-btn').addEventListener('click', fetchAndRender);
  }

  function fetchAndRender() {
    var container = document.getElementById('tech-news-container');
    if (!container) return;

    showLoading(container);

    var prefs = loadPrefs();
    var payload = {
      topicScores: prefs.topicScores || {},
      sourceScores: prefs.sourceScores || {},
      readArticles: prefs.readArticles || [],
      limit: 50
    };

    window.apiFetch('/api/recommend', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    .then(function (res) {
      return res.json();
    })
    .then(function (data) {
      renderArticles(data);
    })
    .catch(function (err) {
      console.error('Failed to fetch articles:', err);
      // Try cached articles
      try {
        var cached = localStorage.getItem(ARTICLES_CACHE_KEY);
        if (cached) {
          renderArticles(JSON.parse(cached));
          return;
        }
      } catch (e) {}
      showError(container, 'Could not load articles. Please check your connection.');
    });
  }

  // Initialize
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fetchAndRender);
  } else {
    fetchAndRender();
  }
})();
