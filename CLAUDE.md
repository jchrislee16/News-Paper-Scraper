# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

News aggregation website with a **split architecture**:
- **This repo (GitHub Pages)** — Frontend only: static HTML/CSS/JS served via GitHub Pages
- **Google Cloud VM** — Backend: Python scripts (RSS fetching, scraping), Flask API (click tracking), database

Users visiting the GitHub Pages site only see frontend code. Server-side scripts, API source, and credentials live exclusively on the VM.

## Architecture

### Data Flow
```
[Google Cloud VM]
RSS Feeds / Web Scraping → Python fetcher → HTML injection → git push trend.html to GitHub
                                                                        ↓
[GitHub Pages]                                                   Static pages served
                                                                        ↓
                                                          User clicks tracked via JS
                                                                        ↓
                                                          Click data POSTed to VM Flask API
```

### Article Update Flow (VM → GitHub)
The VM periodically:
1. Runs `trend_data.py` (fetches RSS, generates HTML cards, updates `trend.html`)
2. `git commit && git push` the updated HTML to this repo
3. GitHub Pages auto-deploys the change

The VM needs a clone of this repo with push access (via SSH key or GitHub token).

### Frontend (this repo)
- `index.html` — Home page
- `trend.html` — Tech news (updated by VM)
- `trend_2.html` — All sources (updated by VM)
- `analytics.html` — Click tracking dashboard (reads from VM API)
- `about.html`, `categories.html` — Static pages
- `js/click-tracker.js` — Tracks article clicks, POSTs to VM API
- `js/custom.js`, `js/user-prefs.js` — UI scripts
- `css/`, `fonts/`, `images/` — Static assets

### Backend (on VM, not in this repo)
Stored separately at `~/News-Paper-Scraper-Backend/`:
- `scripts/trend_data.py` — Fetches Washington Post Tech RSS, generates cards for `trend.html`
- `scripts/trend_display.py` — Multi-source fetcher (9 RSS feeds)
- `scripts/trending_scraper.py` — Advanced scraper with category system (7 categories)
- `api/track_server.py` — Flask API with CORS for click tracking
- `api/clicks.json` — Click data storage
- `requirements.txt` — Python dependencies

## Important Patterns

### API Endpoint Configuration
Frontend JS files reference the VM API at `http://YOUR_VM_IP:5000/api/track`. Replace `YOUR_VM_IP` with the actual VM external IP:
- `js/click-tracker.js` line 8
- `analytics.html` line 138

### HTML Injection via Regex (VM-side)
Scripts on the VM use this pattern to inject article cards:
```python
pattern = r'(<div class="row" id="tech-news-container">).*?(</div>\s*</div>\s*</section>)'
new_html = re.sub(pattern, replacement, html_content, flags=re.DOTALL)
```

### Article Card HTML Structure
Cards use Bootstrap grid (`col-md-6 col-lg-4`) with badge, title, truncated summary, date, and "Read More" link. Tracked links need:
```html
<a href="{url}" class="track-click" data-title="{title}" data-source="{source}" data-category="{category}">
```

### Category System
7 categories with color codes: Technology (#007bff), Politics (#dc3545), World (#28a745), Business (#fd7e14), Science (#6f42c1), Entertainment (#e83e8c), Sports (#20c997).

## Dependencies

Frontend only (all loaded locally or via CDN): Bootstrap 4, jQuery 3.4.1, Owl Carousel, Font Awesome 5, Isotope
