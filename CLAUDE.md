# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

News aggregation website with a **split architecture**:
- **This repo (GitHub Pages)** — Frontend only: static HTML/CSS/JS served via GitHub Pages. GitHub repo slug: `jchrislee16/News-Paper-Scraper` (the `main` branch is the deploy branch, and `config.js` re-fetches its own source from `raw.githubusercontent.com/jchrislee16/News-Paper-Scraper/main/js/config.js`).
- **Cloud VM (Azure)** — Backend: Python scripts (RSS fetching, scraping), Flask API, database

Users visiting the GitHub Pages site only see frontend code. Server-side scripts, API source, and credentials live exclusively on the VM. Do **not** commit backend files, credentials, or `*.pem` keys to this repo.

## Build / Run / Test

There is **no build system, package manager, or test suite** in this repo — it's plain static files served directly by GitHub Pages (Jekyll passthrough via the empty `_config.yml`).

- **Preview locally:** open the `.html` files directly, or `python3 -m http.server` from the repo root (some JS expects a real origin for `fetch`).
- **Compile SCSS:** `css/style.scss` → `css/style.css`. Use the `sass` CLI (e.g. `sass css/style.scss css/style.css`) — there is no npm script wired up, and `sass` is **not currently installed on this machine**. `css/style.css` and `css/style.css.map` are committed, so the site ships the checked-in CSS; if you can't run `sass`, edit both `.scss` and `.css` and say so.
- **Deploy:** push to `main`; GitHub Pages auto-deploys.
- **Check JS before pushing:** there are no tests, so `node --check js/<file>.js` is the only automated verification available. Everything else is verified in the browser console.
- **Reset personalization state while testing:** `localStorage.removeItem('newsUserPrefs'); localStorage.removeItem('clickCounts'); localStorage.removeItem('cachedArticles')`.

The working directory also contains untracked, gitignored artifacts (`venv/`, `free-server_key.pem`) — leave them alone; they are not part of the deployed site.

## Architecture

### Data Flow
```
[Azure VM]
RSS Feeds / Web Scraping → Python fetcher → articles stored on VM → served by Flask API
                                                                        ↓
[GitHub Pages]                                                   Static pages served
                                                                        ↓
                                            Browser JS fetches /api/recommend (trend_2.html)
                                                                        ↓
                                            Clicks recorded in localStorage (client-only)
```

### One rendering model
`trend_2.html` is the only article feed. **Client-side dynamic feed.** Loads, in this order, `config.js` → `click-tracker.js` → `user-prefs.js` → `recommend.js` → `news-feed.js` (the order matters, see Ranking). On load, `news-feed.js` POSTs to `/api/recommend` a payload of `{ clicks, topicScores, sourceScores, readArticles, limit: 100 }` — where `clicks` is the "soup": clicked-article titles pulled from `localStorage.clickCounts` that the backend turns into a TF-IDF vector for ranking. It passes the response through `window.getRecommendedNews()` and renders the result into `#tech-news-container` as a **flat list in final merged order** (no per-category sections, and nothing re-sorts afterwards), caching the raw response in `localStorage.cachedArticles` as an offline/API-down fallback. No server-side HTML injection here.

### Ranking — one merged pass (`js/recommend.js`)
Order on `trend_2.html` is decided in exactly one place: `window.getRecommendedNews(articles)`, called by `news-feed.js` on the article array *before* render. It ranks data, not DOM. **Historically this was two passes** (server ranked, then `user-prefs.js` re-sorted the cards on different criteria and partly overwrote the server's work); they were merged on 2026-08-20. `user-prefs.js` now only decorates — it no longer sorts.

The merged score blends two signals:

| signal | source | what it means |
|---|---|---|
| **server** | `article.rank_score` from `/api/recommend` | cosine similarity to the TF-IDF soup of clicked titles — what the article is *about* |
| **client** | `0.7 × topicScore + 0.3 × sourceScore` from `newsUserPrefs` | which feeds/categories you keep returning to |

**Both are min-max normalized to 0–1 across the returned list before blending — never add them raw.** Measured live: `rank_score` spans only `0.143–0.196` when you have clicks but `0.567–0.599` at cold start, so its discriminating range is ~0.05 wide *and its absolute position moves with mode*, while the client blend spans 0–~0.4. A raw `0.5·server + 0.5·client` lets the client score bulldoze the server signal every time.

Then, in order:
1. `blended = 0.6 × serverNorm + 0.4 × clientNorm` (`SERVER_WEIGHT`/`CLIENT_WEIGHT`). Server is weighted higher because it reads article *text*; the client half is topic+source, which is ~91% one signal (see "Category is just source" below).
2. **Cold start:** if `readArticles.length < 3` (`MIN_CLICKS`) or both score vectors are empty, `clientWeight` drops to 0 and the server takes the full 1.0. Pure content matching until there's real history.
3. **Read articles sink:** `score = blended − 3.0` (`READ_PENALTY`) if already read. This must exceed the whole score range — an earlier `+0.5` unread *boost* was not decisive enough and let an article that topped both signals hold slot #1 after being read. At 3.0 the read band is `[-3,-2]` and unread is `[0,1]`, so even worst-case diversification (3 × 0.4) can't interleave them.
4. **MMR-style diversification** picks the final order: repeatedly take the best remaining article, minus `PENALTY = 0.4` per occurrence of its topic in the last `LOOKBACK = 3` slots. Runs even at cold start, because raw server order clumps hard by category on its own (measured: longest same-category run 4 → 2 after diversification).

`recommend.js` reuses `TOPIC_MAP` and the prefs helpers via `window.NewsPrefs` (exported by `user-prefs.js`), which is **why `user-prefs.js` must load first**. It falls back to a minimal inline implementation if that global is missing.

**Debugging:** every card renders a `.prefs-score-debug` block (built in `news-feed.js` from the `article._rank` breakdown the ranker attaches) showing both raw and normalized signals, their weights, the read penalty, and the diversity-penalized value that won the slot. `window.togglePrefsDebug()` shows/hides them; set `window.PREFS_DEBUG_SCORES = false` before load to start hidden. **The default is on** (`user-prefs.js` sets `PREFS_DEBUG_SCORES = true` when undefined), so the deployed site currently shows the arithmetic to every visitor — flip that default in `user-prefs.js` when you want a clean feed. `window.RANK_WEIGHTS` exposes the constants.

**Note:** `article.score` is a *popularity* field that is `0` for nearly every article — it is not the ranking signal and the "Score:" text on cards almost never renders. The relevance number is `rank_score`.

### Score bookkeeping — the decay vector
Both `topicScores` and `sourceScores` update identically (`applyDecay` in `user-prefs.js`, mirrored in the `click-tracker.js` fallback): scale the whole vector to 95%, then add `0.05` to the clicked key. Because it divides by the current total first, a vector left summing to >1 (e.g. from the old raw-count path) self-heals back to 1.0 on the next click.

**Known quirk:** a single click applies the decay **twice** — `click-tracker.js` calls `window.recordClick()`, and `user-prefs.js`'s own `decorateCards` listener on the same anchor calls `recordClick()` again. Keep this in mind when tuning the `0.05` step.

### Frontend (this repo)
**Only `trend_2.html` loads the app JS.** `index.html`, `about.html`, `categories.html` load just jQuery/Bootstrap/Owl/Isotope/`custom.js` — no `config.js`, no tracking, no feed. So an API or ranking change can only be observed on `trend_2.html`, and click tracking does not run anywhere else.

- `index.html` — Home page
- `trend_2.html` — Dynamic personalized feed (fetches `/api/recommend` at runtime); the only article feed
- `about.html`, `categories.html` — Static pages
- `js/config.js` — Sets `window.NEWS_API_BASE`; provides `window.apiFetch()` retry wrapper
- `js/news-feed.js` — Dynamic feed renderer (used by `trend_2.html`)
- `js/click-tracker.js` — **localStorage-only** click tracking (no API). Logs to `clickCounts` (100-item cap) AND, as a fallback when `window.recordClick` (from `user-prefs.js`) is absent, writes `newsUserPrefs` itself: decay-vector update (`topicScores`/`sourceScores` scaled to 95%, clicked key +0.05) plus `readArticles` (cap 100) and `readTitles` (cap 50). It also `preventDefault()`s the click and re-opens the URL via `window.open` after 100 ms — so tracked links are synthetic navigations and can trip popup blockers.
- `js/recommend.js` — **the ranker.** `window.getRecommendedNews(articles)` — the single sorting mechanism; see Ranking above.
- `js/user-prefs.js` — Personalization state + card decoration (localStorage). Owns `TOPIC_MAP`, the decay vectors, and the filter bar / bookmarks / badges / read styling, and exports `window.NewsPrefs` for `recommend.js`. **Does not sort** — that moved to `recommend.js`.
- `js/custom.js` — UI scripts
- `css/`, `fonts/`, `images/` — Static assets

### Backend (on VM, not in this repo)
Stored separately at `~/News-Paper-Scraper-Backend/`:
- `scripts/` — RSS fetchers / scrapers that collect articles and store them for the API to serve
- `api/track_server.py` — Flask API (CORS-enabled), runs on port 5000, exposed via a Cloudflare tunnel
- `requirements.txt` — Python dependencies

**Live API endpoints** (Flask):
- `POST /api/recommend` — personalized article ranking (used by `news-feed.js`) ✅
- `GET /api/articles` — all articles, unranked ✅
- `GET /api/health` — health check ✅

`analytics.html` (a click dashboard reading a `GET /api/track` that was never built) was deleted on 2026-08-06. If you build anonymous per-article counters later, the page is recoverable from git history — it expects `{success, total_clicks, unique_articles, articles: {id: {category, source, count}}}`.

## Important Patterns

### API Endpoint Configuration
All API URLs are centralized in `js/config.js`, which sets `window.NEWS_API_BASE` (a `trycloudflare.com` tunnel URL that **changes every time the tunnel restarts**).
- `js/news-feed.js` calls the API via `window.apiFetch(path, options)` (retry + reconnect wrapper)

**To change the API URL, edit only `js/config.js`.** On API failure, `config.js` re-fetches its own raw source from GitHub (`raw.githubusercontent.com/.../js/config.js`) to pick up a new tunnel URL, shows a reconnecting overlay, and retries up to 5 times. The VM can auto-update this file and git push.

### Article container
`#tech-news-container` is the anchor `news-feed.js` renders into (in final ranked order) and `user-prefs.js` decorates. Nothing re-sorts it after render.

**Note:** the VM previously had a script that regex-injected static cards into `trend.html` and git-pushed the result. `trend.html` was deleted on 2026-07-30; if that script still runs on the VM it will recreate the file — disable it there.

### Article Card HTML Structure
Cards use Bootstrap grid (`col-md-6 col-lg-4`) with source/category badges, title, summary, date, a "Read More" link, and the `.prefs-score-debug` block. (The `#N` rank badge was removed on 2026-07-30.)

**The wrapper class is a contract.** `user-prefs.js` finds cards with `container.querySelectorAll('.col-md-6')` and reads each URL from `a.btn, a.track-click`; category/source come from the link's `data-*` attrs, falling back to badge text. Rename the column class or drop `track-click` and decoration, bookmarks, read styling, and the filter bar all silently stop working — with no error. Tracked links must carry the data attributes that `click-tracker.js` and `user-prefs.js` read:
```html
<a href="{url}" class="track-click" data-title="{title}" data-source="{source}" data-category="{category}">
```

`renderCard()` builds this by string concatenation into `innerHTML`; only `data-title` is escaped (quotes only). Article `title`/`summary`/`url` from the API are interpolated raw, i.e. the API response is trusted markup. Keep that in mind before pointing the feed at an untrusted source.

### Category System
~10 categories, each with a color code (see `CATEGORY_COLORS` in `js/news-feed.js` and the badge classes in `categories.html`): Technology (#007bff), Politics (#dc3545), World (#28a745), Business (#fd7e14), Science (#6f42c1), Entertainment (#e83e8c), Sports (#20c997), Health (#28a745, same as World), Environment (#17a2b8), Education (#6610f2), plus a General fallback (#6c757d). Each category is tracked independently.

### User Preferences System (`js/user-prefs.js`)
Client-side personalization via localStorage (key `newsUserPrefs`) — **nothing is sent to the server**. Maps display category names → normalized DB topic keys (`TOPIC_MAP` / `TOPIC_DISPLAY`), e.g. Technology→tech, Business→business. Tracks `topicScores` and `sourceScores`, plus `readArticles`/`savedArticles`. **Decoration only — it does not reorder anything** (ordering moved to `recommend.js`; see Ranking). Adds a filter bar (All/Unread/Saved), bookmark buttons, "For You" badges, and read indicators. Includes migration logic for old `categoryScores`. Expose-and-reinit: `news-feed.js` calls `window.reinitUserPrefs()` and `window.reinitClickTracking()` after rendering dynamic cards.

### SCSS
`css/style.scss` compiles to `css/style.css`. Key variables: `$primary1: #ffbe33`, `$primary2: #222831`. Fonts: Open Sans (main), Dancing Script (accent).

## .gitignore Notes
Backend files (`scripts/`, `api/`, `requirements.txt`, `*.sql`) are gitignored — they live on the VM only. Also excluded: JSON cache files (`*_news_*.json`), `venv/`, `*.pem` keys, and `gcloud-shared-key`.

## Dependencies

Frontend only (loaded locally or via CDN): Bootstrap 4, jQuery 3.4.1, Owl Carousel, Font Awesome 5, Isotope.
