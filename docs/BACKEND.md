# The news-feed backend

Static frontend on GitHub Pages, Flask API on an Azure VM, reached through an
ephemeral Cloudflare quick tunnel. Revived 2026-11-06 from
`~/Desktop/News-Paper-Scraper-Archive-2026-09-03/backend-archive-2026-09-03.zip`
after being archived off-VM on 2026-09-03.

**The interactive page is [`trend_2.html`](../trend_2.html), not `index.html`.**
`index.html` is the Bootstrap template's informational landing page: it has no
`#tech-news-container` and loads none of the feed scripts. `trend_2.html` loads
`config.js`, `click-tracker.js`, `user-prefs.js`, `recommend.js` and
`news-feed.js`, and is the one that renders the article list.

## On the VM

| Unit | What |
|---|---|
| `news-api.service` | Flask, `api/track_server.py`, port 5000, `MemoryMax=200M` |
| `news-tunnel.service` | `cloudflared tunnel --url http://localhost:5000`, `MemoryMax=120M` |
| crontab | `*/30 * * * *` → `scripts/fetch_articles.py` (7 RSS feeds) |

Both are systemd units, so they come back after a reboot. The pre-archive setup
used `nohup`/`setsid` and did not. The memory caps matter: the box has 894 MB and
also runs MySQL for the Employee Database.

```bash
sudo systemctl status news-api news-tunnel
journalctl -u news-tunnel -n 50
tail -f ~/News-Paper-Scraper-Backend/logs/fetcher.log
```

## How the frontend finds a moving API — and what was broken

A Cloudflare *quick* tunnel gets a new random hostname on every restart. The
frontend is static, so it needs telling. `js/config.js` carries the current URL
and the client-side recovery:

- `window.apiFetch(path)` wraps `fetch`, retries 5 times at 5s intervals, and
  shows a "Reconnecting to server…" overlay.
- Between retries it calls `fetchLatestUrl()`, which re-reads `config.js` from
  GitHub raw and picks up a changed `NEWS_API_BASE` **without a page reload**.
- `js/news-feed.js` calls `apiFetch('/api/recommend')`.

**That half was always built. The VM half never existed.** The file's own comment
claimed "auto-updated by the VM when the tunnel URL changes", but the archived
crontab contained only the fetcher, and nothing in the backend referenced
`git push`, `raw.githubusercontent` or `NEWS_API_BASE`. The fingerprint: the
committed URL was `not-timer-protective-aquarium` while the tunnel log's last
actual URL was `repository-substantially-hockey-algebra`. They never matched,
because nothing ever wrote one back.

Without a writer the retry loop is a closed circuit — it re-reads the same stale
file five times and gives up.

### The missing writer

`scripts/publish_tunnel_url.sh`, run by `news-tunnel.service` as
`ExecStartPost`, so every tunnel restart republishes. It:

1. takes the **last** URL in `logs/tunnel.log` (the log is appended across
   restarts; the first match would be a long-dead tunnel),
2. **health-checks it before publishing** — announcing a URL that does not answer
   is worse than leaving the old one, because the page would then show the
   reconnect overlay against a fresh dead end,
3. rewrites only the `window.NEWS_API_BASE` assignment, anchored so the
   `CONFIG_URL` constant two lines below it cannot be clobbered,
4. exits without a commit if the URL is unchanged,
5. commits and pushes to `main`.

Run it by hand any time; it is idempotent:

```bash
~/News-Paper-Scraper-Backend/scripts/publish_tunnel_url.sh
```

### Deploy key

The push uses `~/.ssh/id_pages_deploy`, generated on the VM so the private half
has never moved. Add the public half to
**GitHub → repo → Settings → Deploy keys → Add deploy key**, with
**Allow write access** checked.

Worth knowing what that grants: a deploy key is scoped to this one repository,
but `main` is the Pages branch, so a compromise of the VM means an attacker
could publish to the live site. The script only ever touches `js/config.js`, and
the key is write-scoped to this repo alone — but it is a real trust edge, not a
formality.

Until the key is added, pushes fail and the tunnel URL has to be updated by hand
(`sed` the line in `js/config.js`, commit, push). Everything else works.

## Propagation delay

GitHub Pages takes roughly 30–60s to publish a changed `config.js`. During that
window a visitor's page shows the reconnect overlay. That is the system working:
`fetchLatestUrl()` keeps re-reading until the new URL appears.
