#!/usr/bin/env python3
"""
Trending News Scraper
Scrapes "Most Read" and trending sections from popular news sites.
No API keys required - fully standalone.
"""

import requests
from bs4 import BeautifulSoup
import json
import os
import re
from datetime import datetime
from urllib.parse import urljoin
from collections import defaultdict

# Request headers to mimic browser
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

# Category definitions with keywords
CATEGORIES = {
    "Technology": {
        "keywords": ["ai", "artificial intelligence", "tech", "software", "app", "google", "apple", "microsoft",
                     "amazon", "meta", "nvidia", "chip", "semiconductor", "robot", "cyber", "hack", "data",
                     "algorithm", "startup", "silicon valley", "openai", "chatgpt", "machine learning",
                     "computer", "internet", "digital", "smartphone", "iphone", "android", "cloud", "api"],
        "sources": ["Hacker News", "Reddit r/technology"],
        "color": "#007bff"
    },
    "Politics": {
        "keywords": ["trump", "biden", "congress", "senate", "election", "vote", "democrat", "republican",
                     "president", "governor", "mayor", "legislation", "bill", "law", "court", "judge",
                     "supreme court", "political", "campaign", "immigration", "border", "policy", "federal"],
        "sources": [],
        "color": "#dc3545"
    },
    "World": {
        "keywords": ["ukraine", "russia", "china", "europe", "asia", "africa", "middle east", "war",
                     "military", "troops", "nato", "un", "united nations", "diplomatic", "embassy",
                     "international", "foreign", "global", "country", "nation", "invasion", "conflict"],
        "sources": ["Reddit r/worldnews"],
        "color": "#28a745"
    },
    "Business": {
        "keywords": ["stock", "market", "economy", "inflation", "fed", "bank", "invest", "ceo", "company",
                     "billion", "million", "profit", "revenue", "ipo", "merger", "acquisition", "wall street",
                     "dow", "nasdaq", "s&p", "crypto", "bitcoin", "earnings", "layoff", "job"],
        "sources": [],
        "color": "#fd7e14"
    },
    "Science": {
        "keywords": ["nasa", "space", "planet", "star", "climate", "environment", "research", "study",
                     "scientist", "discovery", "species", "ocean", "earth", "moon", "mars", "rocket",
                     "medicine", "health", "disease", "virus", "vaccine", "cancer", "brain", "dna"],
        "sources": [],
        "color": "#6f42c1"
    },
    "Entertainment": {
        "keywords": ["movie", "film", "tv", "show", "netflix", "disney", "actor", "actress", "celebrity",
                     "music", "album", "concert", "game", "gaming", "playstation", "xbox", "nintendo",
                     "oscar", "grammy", "emmy", "streaming", "youtube", "tiktok", "viral"],
        "sources": [],
        "color": "#e83e8c"
    },
    "Sports": {
        "keywords": ["nfl", "nba", "mlb", "nhl", "soccer", "football", "basketball", "baseball", "hockey",
                     "tennis", "golf", "olympic", "championship", "playoff", "super bowl", "world cup",
                     "team", "player", "coach", "score", "game", "match", "win", "championship"],
        "sources": [],
        "color": "#20c997"
    }
}


def categorize_article(article):
    """Determine the category of an article based on title, URL, and source."""
    title = article.get("title", "").lower()
    link = article.get("link", "").lower()
    source = article.get("source", "")

    # Check source-based categorization first
    for category, config in CATEGORIES.items():
        if source in config.get("sources", []):
            return category

    # Check keywords in title and URL
    best_match = None
    best_score = 0

    for category, config in CATEGORIES.items():
        score = 0
        for keyword in config.get("keywords", []):
            if keyword in title:
                score += 2  # Title matches worth more
            if keyword in link:
                score += 1

        if score > best_score:
            best_score = score
            best_match = category

    return best_match if best_match else "General"


def get_filename():
    """Generate dated cache filename."""
    time = datetime.now().strftime("%Y%m%d")
    return f"trending_news_{time}.json"


def today_cache_exists():
    """Check if today's cache already exists."""
    return os.path.exists(get_filename())


def fetch_bbc_most_read():
    """Scrape BBC News Most Read section."""
    articles = []
    url = "https://www.bbc.com/news"

    try:
        response = requests.get(url, headers=HEADERS, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")

        # Find the Most Read section by looking for h2 with "Most Read" text
        seen_urls = set()
        for section in soup.find_all(["section", "div"]):
            h2 = section.find("h2")
            if h2 and "most read" in h2.get_text().lower():
                links = section.find_all("a", href=True)

                for link in links:
                    href = link.get("href", "")
                    if href and "/news/" in href and href not in seen_urls:
                        full_url = urljoin("https://www.bbc.com", href)
                        title = link.get_text(strip=True)

                        # Remove leading numbers (e.g., "1Andrew..." -> "Andrew...")
                        title = re.sub(r"^\d+", "", title).strip()

                        if title and len(title) > 10:
                            seen_urls.add(href)
                            articles.append({
                                "title": title,
                                "link": full_url,
                                "source": "BBC Most Read",
                                "trending_score": 10,  # High score for most-read
                                "published": datetime.now().strftime("%a, %d %b %Y")
                            })
                break  # Found the Most Read section, stop searching

        print(f"BBC Most Read: {len(articles)} articles")

    except Exception as e:
        print(f"Error fetching BBC: {e}")

    return articles[:10]  # Limit to top 10


def fetch_hacker_news():
    """Fetch top stories from Hacker News (uses their simple endpoints)."""
    articles = []

    try:
        # HN provides JSON endpoints without authentication
        top_stories_url = "https://hacker-news.firebaseio.com/v0/topstories.json"
        response = requests.get(top_stories_url, timeout=10)
        response.raise_for_status()
        story_ids = response.json()[:15]  # Get top 15 story IDs

        for i, story_id in enumerate(story_ids):
            try:
                story_url = f"https://hacker-news.firebaseio.com/v0/item/{story_id}.json"
                story_resp = requests.get(story_url, timeout=5)
                story = story_resp.json()

                if story and story.get("type") == "story" and story.get("url"):
                    articles.append({
                        "title": story.get("title", ""),
                        "link": story.get("url", ""),
                        "source": "Hacker News",
                        "trending_score": story.get("score", 0),  # HN upvotes as score
                        "published": datetime.now().strftime("%a, %d %b %Y"),
                        "summary": f"Score: {story.get('score', 0)} | Comments: {story.get('descendants', 0)}"
                    })
            except Exception as e:
                continue

        print(f"Hacker News: {len(articles)} articles")

    except Exception as e:
        print(f"Error fetching Hacker News: {e}")

    return articles


def fetch_reddit_news():
    """Fetch top posts from r/news and r/worldnews (Reddit serves JSON without auth)."""
    articles = []
    subreddits = ["news", "worldnews", "technology"]

    for subreddit in subreddits:
        try:
            url = f"https://www.reddit.com/r/{subreddit}/hot.json?limit=10"
            response = requests.get(url, headers=HEADERS, timeout=10)
            response.raise_for_status()
            data = response.json()

            for post in data.get("data", {}).get("children", []):
                post_data = post.get("data", {})

                # Skip self posts and stickied posts
                if post_data.get("is_self") or post_data.get("stickied"):
                    continue

                articles.append({
                    "title": post_data.get("title", ""),
                    "link": post_data.get("url", ""),
                    "source": f"Reddit r/{subreddit}",
                    "trending_score": post_data.get("score", 0),  # Reddit upvotes
                    "published": datetime.now().strftime("%a, %d %b %Y"),
                    "summary": f"Upvotes: {post_data.get('score', 0):,} | Comments: {post_data.get('num_comments', 0):,}"
                })

            print(f"Reddit r/{subreddit}: fetched")

        except Exception as e:
            print(f"Error fetching r/{subreddit}: {e}")

    print(f"Reddit total: {len(articles)} articles")
    return articles


def fetch_guardian_most_viewed():
    """Scrape The Guardian's most viewed section from homepage."""
    articles = []
    url = "https://www.theguardian.com/uk"

    try:
        response = requests.get(url, headers=HEADERS, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")

        seen_urls = set()

        # Look for "Most viewed" section
        for section in soup.find_all(["section", "div", "aside"]):
            heading = section.find(["h2", "h3"])
            if heading and "most viewed" in heading.get_text().lower():
                links = section.find_all("a", href=True)
                for link in links:
                    href = link.get("href", "")
                    title = link.get_text(strip=True)

                    if href and title and len(title) > 15 and href not in seen_urls:
                        # Remove leading numbers
                        title = re.sub(r"^\d+\s*", "", title).strip()
                        seen_urls.add(href)
                        articles.append({
                            "title": title,
                            "link": href if href.startswith("http") else f"https://www.theguardian.com{href}",
                            "source": "Guardian Most Viewed",
                            "trending_score": 8,
                            "published": datetime.now().strftime("%a, %d %b %Y")
                        })
                break

        # Fallback: get featured articles from homepage
        if not articles:
            for link in soup.find_all("a", href=True):
                href = link.get("href", "")
                # Look for article links
                if "/article/" in href or "/2026/" in href or "/2025/" in href:
                    title = link.get_text(strip=True)
                    if title and len(title) > 20 and href not in seen_urls:
                        seen_urls.add(href)
                        articles.append({
                            "title": title,
                            "link": href if href.startswith("http") else f"https://www.theguardian.com{href}",
                            "source": "The Guardian",
                            "trending_score": 7,
                            "published": datetime.now().strftime("%a, %d %b %Y")
                        })
                        if len(articles) >= 10:
                            break

        print(f"Guardian: {len(articles)} articles")

    except Exception as e:
        print(f"Error fetching Guardian: {e}")

    return articles[:10]


def fetch_npr_news():
    """Scrape NPR's homepage for top stories."""
    articles = []
    url = "https://www.npr.org/sections/news/"

    try:
        response = requests.get(url, headers=HEADERS, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")

        # NPR article cards
        for article in soup.find_all("article", class_="item")[:10]:
            link = article.find("a", href=True)
            title_elem = article.find(["h2", "h3"])

            if link and title_elem:
                articles.append({
                    "title": title_elem.get_text(strip=True),
                    "link": link.get("href"),
                    "source": "NPR",
                    "trending_score": 7,
                    "published": datetime.now().strftime("%a, %d %b %Y")
                })

        print(f"NPR: {len(articles)} articles")

    except Exception as e:
        print(f"Error fetching NPR: {e}")

    return articles


def remove_duplicates(articles):
    """Remove duplicate articles by URL."""
    seen_urls = set()
    unique = []

    for article in articles:
        url = article.get("link", "")
        # Normalize URL
        url = url.rstrip("/").lower()

        if url and url not in seen_urls:
            seen_urls.add(url)
            unique.append(article)

    return unique


def sort_by_trending(articles):
    """Sort articles by trending score (highest first)."""
    return sorted(articles, key=lambda x: x.get("trending_score", 0), reverse=True)


def save_to_json(data, filename):
    """Save articles to JSON cache."""
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)


def load_from_json(filename):
    """Load articles from JSON cache."""
    with open(filename, "r", encoding="utf-8") as f:
        return json.load(f)


def generate_article_card(article, rank=None):
    """Generate Bootstrap card HTML for an article."""
    title = article.get("title", "")
    link = article.get("link", "#")
    published = article.get("published", "")
    summary = article.get("summary", "")
    source = article.get("source", "News")
    score = article.get("trending_score", 0)

    # Add rank badge for top articles
    rank_badge = ""
    if rank and rank <= 3:
        colors = {1: "#ff4444", 2: "#ff8800", 3: "#ffbb00"}
        rank_badge = f'<span class="badge" style="background-color: {colors[rank]}; color: #fff; padding: 3px 8px; border-radius: 50%; font-size: 11px; margin-right: 5px;">#{rank}</span>'

    # Score indicator
    if score > 100:
        score_text = f"<small style='color: #28a745;'>Score: {score:,}</small>"
    else:
        score_text = ""

    # Truncate summary if too long
    if summary and len(summary) > 150:
        summary = summary[:150] + "..."

    # Escape title for data attribute
    escaped_title = title.replace('"', '&quot;').replace("'", "&#39;")
    category = article.get("category", "General")

    return f'''          <div class="col-md-6 col-lg-4 mb-4">
            <div class="card h-100" style="border: 1px solid #ddd; border-radius: 8px; overflow: hidden;">
              <div class="card-body">
                {rank_badge}<span class="badge" style="background-color: #ffbe33; color: #fff; padding: 5px 10px; border-radius: 4px; font-size: 12px;">{source}</span>
                <h5 class="card-title mt-2" style="font-weight: bold; color: #222;">{title}</h5>
                <p class="card-text" style="color: #666; font-size: 14px;">{summary}</p>
                <p style="color: #999; font-size: 12px;"><i class="fa fa-calendar"></i> {published} {score_text}</p>
                <a href="{link}" target="_blank" class="btn track-click" style="background-color: #222; color: #fff; padding: 8px 16px; border-radius: 4px; font-size: 14px;" data-title="{escaped_title}" data-source="{source}" data-category="{category}">Read More</a>
              </div>
            </div>
          </div>'''


def group_by_category(articles):
    """Group articles by their category and return top 3 per category."""
    categorized = defaultdict(list)

    for article in articles:
        category = categorize_article(article)
        article["category"] = category
        categorized[category].append(article)

    # Sort each category by trending score and take top 3
    result = {}
    for category, items in categorized.items():
        sorted_items = sorted(items, key=lambda x: x.get("trending_score", 0), reverse=True)
        result[category] = sorted_items[:3]

    return result


def generate_category_section(category, articles):
    """Generate HTML section for a category with its top 3 articles."""
    # Get category color
    color = CATEGORIES.get(category, {}).get("color", "#6c757d")

    # Generate cards with rank
    cards = []
    for i, article in enumerate(articles):
        cards.append(generate_article_card(article, rank=i + 1))

    cards_html = "\n".join(cards)

    return f'''
        <!-- {category} Section -->
        <div class="category-section mb-5">
          <h3 style="color: {color}; border-bottom: 3px solid {color}; padding-bottom: 10px; margin-bottom: 20px;">
            <i class="fa fa-fire" style="margin-right: 8px;"></i>{category}
          </h3>
          <div class="row">
{cards_html}
          </div>
        </div>'''


def update_trend_html(articles):
    """Inject categorized article sections into trend_2.html."""
    html_path = os.path.join(os.path.dirname(__file__), "..", "trend_2.html")

    with open(html_path, "r", encoding="utf-8") as f:
        html_content = f.read()

    # Group articles by category
    categorized = group_by_category(articles)

    # Define category display order (most important first)
    category_order = ["Technology", "Politics", "World", "Business", "Science", "Entertainment", "Sports", "General"]

    # Generate sections for each category
    sections = []
    total_articles = 0
    for category in category_order:
        if category in categorized and categorized[category]:
            sections.append(generate_category_section(category, categorized[category]))
            total_articles += len(categorized[category])

    sections_html = "\n".join(sections)

    # Replace content in tech-news-container - use a different pattern that captures just the container
    pattern = r'(<div class="row" id="tech-news-container">).*?(</div>\s*</div>\s*</section>)'
    replacement = rf'\1\n{sections_html}\n      \2'

    new_html = re.sub(pattern, replacement, html_content, flags=re.DOTALL)

    with open(html_path, "w", encoding="utf-8") as f:
        f.write(new_html)

    print(f"Updated trend_2.html with {total_articles} articles across {len(sections)} categories")


def main():
    """Main function to fetch, process, and display trending news."""
    filename = get_filename()

    if not today_cache_exists():
        print("Fetching trending news from multiple sources...")
        print("-" * 50)

        # Fetch from all sources
        all_articles = []

        # High-quality trending sources
        all_articles.extend(fetch_bbc_most_read())
        all_articles.extend(fetch_hacker_news())
        all_articles.extend(fetch_reddit_news())
        all_articles.extend(fetch_guardian_most_viewed())
        all_articles.extend(fetch_npr_news())

        print("-" * 50)
        print(f"Total fetched: {len(all_articles)} articles")

        # Remove duplicates
        unique_articles = remove_duplicates(all_articles)
        print(f"After deduplication: {len(unique_articles)} articles")

        # Sort by trending score
        sorted_articles = sort_by_trending(unique_articles)

        # Save to cache
        save_to_json(sorted_articles, filename)
        print(f"Saved to {filename}")
    else:
        print(f"Using cached data from {filename}")

    # Load and display
    articles = load_from_json(filename)

    # Update HTML with categorized view
    update_trend_html(articles)

    # Print categorized results for verification
    categorized = group_by_category(articles)
    print("\nTop 3 per Category:")
    for category in ["Technology", "Politics", "World", "Business", "Science", "Entertainment", "Sports", "General"]:
        if category in categorized and categorized[category]:
            print(f"\n  {category}:")
            for i, article in enumerate(categorized[category], 1):
                print(f"    {i}. {article['title'][:55]}...")


if __name__ == "__main__":
    main()
