# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

News aggregation static website that fetches articles from RSS feeds using Python scripts and displays them on Bootstrap-based HTML pages.

## Commands

```bash
# Setup (first time)
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Fetch tech news (single-source, updates trend.html)
python3 scripts/trend_data.py

# Fetch all news (multi-source, updates trend_2.html)
python3 scripts/trend_display.py

# Fetch TRENDING news by popularity (updates trend_2.html)
source venv/bin/activate && python3 scripts/trending_scraper.py
```

No build step required for frontend - static HTML/CSS/JS served directly.

## Architecture

### Data Flow
```
RSS Feeds → Python fetcher → JSON cache (dated) → HTML injection → Static pages
```

### Key Components

**Python Scripts (`scripts/`):**
- `trend_data.py` - Fetches from 6 tech RSS sources, generates cards for `trend.html`
- `trend_display.py` - Fetches from 9 sources (tech + general), generates cards for `trend_2.html`
- `trending_scraper.py` - Scrapes "Most Read" sections from BBC, Guardian, NPR + Reddit/HN trending (updates `trend_2.html`)

All scripts:
1. Check for existing dated JSON cache (`[type]_YYYYMMDD.json`)
2. Skip fetch if today's cache exists
3. Use `feedparser` to parse RSS feeds
4. Deduplicate articles by URL
5. Inject generated HTML cards into pages using regex replacement on `id="tech-news-container"`

**Frontend Pages:**
- `index.html` - Homepage
- `trend.html` - Tech news (auto-updated by trend_data.py)
- `trend_2.html` - All sources news (auto-updated by trend_display.py)
- `about.html`, `categories.html` - Static pages

**Frontend Libraries (local copies):**
- Bootstrap 4, jQuery 3.4.1, Owl Carousel, Isotope, Font Awesome

### RSS Sources
Tech: Washington Post Tech, Ars Technica, TechCrunch, Wired, The Verge, MIT Tech Review
General: BBC World, NPR, Bloomberg Tech

### Trending Sources (scraped)
- BBC Most Read (homepage widget)
- The Guardian Most Viewed
- NPR Top Stories
- Hacker News (top stories via Firebase API)
- Reddit r/news, r/worldnews, r/technology (JSON endpoints)

## Click Tracking

Track which articles users click on:

```bash
# Start tracking server (Python)
source venv/bin/activate && python3 api/track_server.py

# Or use PHP (if server supports it)
# API endpoint: /api/track.php
```

- `analytics.html` - Dashboard showing click stats by category/source
- `js/click-tracker.js` - Frontend tracking script (auto-loaded)
- `api/track_server.py` - Python Flask tracking API
- `api/track.php` - PHP tracking API alternative
- `api/clicks.json` - Click data storage

## Important Patterns

- Date-stamped JSON caching prevents redundant fetches
- HTML injection uses regex to replace content within `<div id="tech-news-container">` blocks
- Article cards use Bootstrap grid classes: `col-md-6 col-lg-4`
- Click tracking uses `data-*` attributes on links with class `track-click`
