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
- **Compile SCSS:** `css/style.scss` → `css/style.css`. Use the `sass` CLI (e.g. `sass css/style.scss css/style.css`) — there is no npm script wired up.
- **Deploy:** push to `main`; GitHub Pages auto-deploys.
- **Check JS before pushing:** there are no tests, so `node --check js/<file>.js` is the only automated verification available. Everything else is verified in the browser console.
- **Reset personalization state while testing:** `localStorage.removeItem('newsUserPrefs'); localStorage.removeItem('clickCounts'); localStorage.removeItem('cachedArticles')`.

The working directory also contains untracked, gitignored artifacts (`venv/`, `free-server_key.pem`) — leave them alone; they are not part of the deployed site.

## Architecture

### Data Flow
```
[Azure VM]
RSS Feeds / Web Scraping → Python fetcher → HTML injection → git push trend.html to GitHub
                                                                        ↓
[GitHub Pages]                                                   Static pages served
                                                                        ↓
                                            Browser JS fetches /api/recommend (trend_2.html)
                                                                        ↓
                                            Clicks recorded in localStorage (client-only)
```

### Two rendering models — important
The site has two **different** ways article cards get onto a page. Don't confuse them:

1. **`trend.html` — server-injected static cards.** The VM runs a Python script that regex-replaces the card HTML inside `trend.html`, commits, and pushes. The cards are baked into the file. It loads `custom.js` + `user-prefs.js` only (no API calls).
2. **`trend_2.html` — client-side dynamic feed.** Loads `config.js` + `click-tracker.js` + `news-feed.js` + `user-prefs.js`. On load, `news-feed.js` POSTs to `/api/recommend` a payload of `{ clicks, topicScores, sourceScores, readArticles, limit: 100 }` — where `clicks` is the "soup": clicked-article titles pulled from `localStorage.clickCounts` that the backend turns into a TF-IDF vector for ranking. It renders the returned articles into `#tech-news-container` as a **flat list in server-ranked order** (no per-category sections — `user-prefs.js` reorders them afterward, see Ranking below), and caches the full response in `localStorage.cachedArticles` as an offline/API-down fallback. No server-side HTML injection here.

### Ranking happens twice — server, then client
Order on `trend_2.html` is decided in two passes. Changing one without knowing about the other produces confusing results:

1. **Server (TF-IDF "soup")** — `/api/recommend` ranks all articles by similarity to a vector built from the titles the user clicked. `news-feed.js` renders that order as-is, and each card shows the server's `score`.
2. **Client (`user-prefs.js` → `sortByPreference`)** — once `readArticles.length >= 3`, it re-sorts the DOM:
   - Each card scores `0.7 × topicScore + 0.3 × sourceScore` (`TOPIC_WEIGHT`/`SOURCE_WEIGHT`). Both are decay vectors summing to 1.0, so they're on the same scale and blend directly.
   - Unread cards get a flat `+0.5` boost.
   - Final placement is **MMR-style diversified**, not a plain sort: it repeatedly picks the best-scoring card but subtracts `PENALTY = 0.4` per occurrence of that topic in the last `LOOKBACK = 3` slots, so the top topic wins the most slots without clumping 30-in-a-row.

**Debugging the client pass:** `window.PREFS_DEBUG_SCORES` (default `true`) appends a score breakdown to every card — raw topic/source scores, the 70/30 blend, the unread boost, and the penalized value that won the slot. `window.togglePrefsDebug()` flips it from the console.

### Score bookkeeping — the decay vector
Both `topicScores` and `sourceScores` update identically (`applyDecay` in `user-prefs.js`, mirrored in the `click-tracker.js` fallback): scale the whole vector to 95%, then add `0.05` to the clicked key. Because it divides by the current total first, a vector left summing to >1 (e.g. from the old raw-count path) self-heals back to 1.0 on the next click.

**Known quirk:** on `trend_2.html` a single click applies the decay **twice** — `click-tracker.js` calls `window.recordClick()`, and `user-prefs.js`'s own `decorateCards` listener on the same anchor calls `recordClick()` again. `trend.html` doesn't load `click-tracker.js`, so it applies once. Keep this in mind when tuning the `0.05` step.

### Article Update Flow (VM → GitHub, for `trend.html`)
The VM periodically:
1. Runs the fetcher (RSS → generated HTML cards → regex-injected into `trend.html`)
2. `git commit && git push` to this repo
3. GitHub Pages auto-deploys

The VM needs a clone of this repo with push access (SSH key or GitHub token).

### Frontend (this repo)
- `index.html` — Home page
- `trend.html` — Server-injected static article feed (updated by VM)
- `trend_2.html` — Dynamic personalized feed (fetches `/api/recommend` at runtime)
- `analytics.html` — Click dashboard. **Note: it GETs `/api/track`, which does not exist on the backend — this page is currently non-functional.**
- `about.html`, `categories.html` — Static pages
- `js/config.js` — Sets `window.NEWS_API_BASE`; provides `window.apiFetch()` retry wrapper
- `js/news-feed.js` — Dynamic feed renderer (used by `trend_2.html`)
- `js/click-tracker.js` — **localStorage-only** click tracking (no API). Logs to `clickCounts` (100-item cap) AND, as a fallback when `window.recordClick` (from `user-prefs.js`) is absent, applies a decay-vector update to `newsUserPrefs`: existing `topicScores`/`sourceScores` are scaled to 95% and the clicked topic/source gets +0.05, keeping each score set normalized.
- `js/user-prefs.js` — Personalization engine (localStorage)
- `js/custom.js` — UI scripts
- `css/`, `fonts/`, `images/` — Static assets

### Backend (on VM, not in this repo)
Stored separately at `~/News-Paper-Scraper-Backend/`:
- `scripts/` — RSS fetchers / scrapers that generate cards and inject them into `trend.html`
- `api/track_server.py` — Flask API (CORS-enabled), runs on port 5000, exposed via a Cloudflare tunnel
- `requirements.txt` — Python dependencies

**Live API endpoints** (Flask):
- `POST /api/recommend` — personalized article ranking (used by `news-feed.js`) ✅
- `GET /api/articles` — all articles, unranked ✅
- `GET /api/health` — health check ✅
- `GET /api/track` — **referenced by `analytics.html` but never built** ❌

## Important Patterns

### API Endpoint Configuration
All API URLs are centralized in `js/config.js`, which sets `window.NEWS_API_BASE` (a `trycloudflare.com` tunnel URL that **changes every time the tunnel restarts**).
- `js/news-feed.js` calls the API via `window.apiFetch(path, options)` (retry + reconnect wrapper)
- `analytics.html` reads `window.NEWS_API_BASE` directly

**To change the API URL, edit only `js/config.js`.** On API failure, `config.js` re-fetches its own raw source from GitHub (`raw.githubusercontent.com/.../js/config.js`) to pick up a new tunnel URL, shows a reconnecting overlay, and retries up to 5 times. The VM can auto-update this file and git push.

### HTML Injection via Regex (VM-side, for `trend.html`)
VM scripts inject cards with:
```python
pattern = r'(<div class="row" id="tech-news-container">).*?(</div>\s*</div>\s*</section>)'
new_html = re.sub(pattern, replacement, html_content, flags=re.DOTALL)
```
The container `id="tech-news-container"` is the shared anchor — both the VM injector and `news-feed.js` target it.

### Article Card HTML Structure
Cards use Bootstrap grid (`col-md-6 col-lg-4`) with rank badge, source/category badges, title, summary, date, and a "Read More" link. Tracked links must carry the data attributes that `click-tracker.js` and `user-prefs.js` read:
```html
<a href="{url}" class="track-click" data-title="{title}" data-source="{source}" data-category="{category}">
```

### Category System
~10 categories, each with a color code (see `CATEGORY_COLORS` in `js/news-feed.js` and the badge classes in `categories.html`): Technology (#007bff), Politics (#dc3545), World (#28a745), Business (#fd7e14), Science (#6f42c1), Entertainment (#e83e8c), Sports (#20c997), Health (#28a745, same as World), Environment (#17a2b8), Education (#6610f2), plus a General fallback (#6c757d). Each category is tracked independently.

### User Preferences System (`js/user-prefs.js`)
Client-side personalization via localStorage (key `newsUserPrefs`) — **nothing is sent to the server**. Maps display category names → normalized DB topic keys (`TOPIC_MAP` / `TOPIC_DISPLAY`), e.g. Technology→tech, Business→business. Tracks `topicScores` and `sourceScores`, plus `readArticles`/`savedArticles`. Reorders cards after 3+ clicks and adds a filter bar (All/Unread/Saved), bookmark buttons, "For You" badges, and read indicators. Includes migration logic for old `categoryScores`. Expose-and-reinit: `news-feed.js` calls `window.reinitUserPrefs()` and `window.reinitClickTracking()` after rendering dynamic cards.

### SCSS
`css/style.scss` compiles to `css/style.css`. Key variables: `$primary1: #ffbe33`, `$primary2: #222831`. Fonts: Open Sans (main), Dancing Script (accent).

## .gitignore Notes
Backend files (`scripts/`, `api/`, `requirements.txt`, `*.sql`) are gitignored — they live on the VM only. Also excluded: JSON cache files (`*_news_*.json`), `venv/`, `*.pem` keys, and `gcloud-shared-key`.

## Dependencies

Frontend only (loaded locally or via CDN): Bootstrap 4, jQuery 3.4.1, Owl Carousel, Font Awesome 5, Isotope.
