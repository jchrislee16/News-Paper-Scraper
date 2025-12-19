#!/usr/bin/env python3
"""
Trend Display Script
This script will handle trend data processing and analysis from multiple news sources.
"""

import feedparser
import json
import os
import re
from datetime import datetime

rss_urls = [
    # Tech News
    "https://feeds.washingtonpost.com/rss/business/technology",
    "https://feeds.arstechnica.com/arstechnica/technology-lab",
    "https://techcrunch.com/feed/",
    "https://www.wired.com/feed/rss",
    "https://www.theverge.com/rss/index.xml",
    "https://www.technologyreview.com/feed/",
    # General News
    "https://feeds.bbci.co.uk/news/world/rss.xml",
    "https://feeds.npr.org/1001/rss.xml",
    # Business/Finance
    "https://feeds.bloomberg.com/technology/news.rss",
]


def get_filename():
    time = datetime.now().strftime("%Y%m%d")
    filename = f"all_news_{time}.json"
    return filename

def today_news_exists():
    return os.path.exists(get_filename())

def fetch_tech_news():
    articles = []

    for rss_url in rss_urls:
        try:
            feed = feedparser.parse(rss_url)
            for entry in feed.entries[:10]:
                article = {
                    "title": entry.get("title"),
                    "link": entry.get("link"),
                    "published": entry.get("published"),
                    "summary": entry.get("summary"),
                    "source": feed.feed.get("title", rss_url)
                }
                articles.append(article)
        except Exception as e:
            print(f"Error fetching {rss_url}: {e}")

    return articles

def get_today_news(articles):
    today_articles = []
    day = datetime.now().strftime("%a")

    for article in articles:
        date = article.get("published")
        if date and date.startswith(day):
            today_articles.append(article)
    return today_articles

def save_to_json(data, filename):
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)

def load_from_json(filename):
    with open(filename, "r") as f:
        data = json.load(f)
        return data

def remove_duplicates(articles):
    all_links = set()
    unique_articles = []

    for article in articles:
        link = article.get("link")
        if link not in all_links:
            all_links.add(link)
            unique_articles.append(article)
    return unique_articles

# goal: ai new analysis
def score_articles(articles):
    scores = []
    for article in articles:
        score = rate_article(article)
        scores.append(score)
    return scores

def rate_article(article):
    score = 0
    if 20 < len(article.get("title")) < 50:
        score += 1
    keywords = ["technology", "ai"]

    return score

def generate_article_card(article):
    title = article.get("title", "")
    link = article.get("link", "#")
    published = article.get("published", "")
    summary = article.get("summary", "")
    source = article.get("source", "News")

    return f'''        <div class="col-md-6 col-lg-4 mb-4">
          <div class="card h-100" style="border: 1px solid #ddd; border-radius: 8px; overflow: hidden;">
            <div class="card-body">
              <span class="badge" style="background-color: #ffbe33; color: #fff; padding: 5px 10px; border-radius: 4px; font-size: 12px;">{source}</span>
              <h5 class="card-title mt-2" style="font-weight: bold; color: #222;">{title}</h5>
              <p class="card-text" style="color: #666; font-size: 14px;">{summary[:200]}...</p>
              <p style="color: #999; font-size: 12px;"><i class="fa fa-calendar"></i> {published}</p>
              <a href="{link}" target="_blank" class="btn" style="background-color: #222; color: #fff; padding: 8px 16px; border-radius: 4px; font-size: 14px;">Read More</a>
            </div>
          </div>
        </div>'''

def update_trend_html(articles):
    html_path = os.path.join(os.path.dirname(__file__), "..", "trend_2.html")

    with open(html_path, "r", encoding="utf-8") as f:
        html_content = f.read()

    cards_html = "\n".join([generate_article_card(article) for article in articles])

    pattern = r'(<div class="row" id="tech-news-container">).*?(</div>\s*</div>\s*</section>)'
    replacement = rf'\1\n{cards_html}\n      \2'

    new_html = re.sub(pattern, replacement, html_content, flags=re.DOTALL)

    with open(html_path, "w", encoding="utf-8") as f:
        f.write(new_html)

    print(f"Updated trend_2.html with {len(articles)} articles")

if __name__ == "__main__":
    filename = get_filename()

    if not today_news_exists():
        news = fetch_tech_news()
        print(f"Fetched {len(news)} articles from {len(rss_urls)} sources.")

        save_to_json(news, filename)
        print(f"Saved to {filename}")

    articles = load_from_json(filename)

    unique_articles = remove_duplicates(articles)
    print(f"Unique articles: {len(unique_articles)}")

    today_articles = get_today_news(articles)
    print(f"Today's articles: {len(today_articles)}")

    update_trend_html(unique_articles)
