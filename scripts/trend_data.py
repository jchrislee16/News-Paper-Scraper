#!/usr/bin/env python3
"""
Trend Data Script
This script will handle trend data processing and analysis.
"""

import feedparser
import json
import os
from datetime import datetime

rss_url = "https://feeds.washingtonpost.com/rss/business/technology"

def get_filename():
    time = datetime.now().strftime("%Y%m%d")
    filename = f"tech_news_{time}.json"
    return filename

def today_news_exists():
    return os.path.exists(get_filename())

def fetch_tech_news():
    feed = feedparser.parse(rss_url)

    articles = []
    for entry in feed.entries[:10]:
        # Thu, 04 Dec 2025 19:00:00 +0000
        # print(entry.get("published"))

        article = {
            "title": entry.get("title"),
            "link": entry.get("link"),
            # rss provided summary, not ai generated
            "summary": entry.get("summary")
        }
        articles.append(article)
    return articles

def get_today_news(articles):
    today = datetime.now().strftime("%Y%m%d")
    for article in articles:
        date = article.get("published", "")
        print(date)
        if date.startswith(today):
            print("a")

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

if __name__ == "__main__":
    filename = get_filename()
    
    if not today_news_exists():
        news = fetch_tech_news()
        # print(f"fetched {len(news)} tech news articles.")

        save_to_json(news, filename)
        # print(f"saved to {filename}")
    
    articles = load_from_json(filename)
    # print(articles)

    unique_articles = remove_duplicates(articles)
    # print(unique_articles)

    get_today_news(articles)