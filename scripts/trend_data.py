#!/usr/bin/env python3
"""
Trend Data Script
This script will handle trend data processing and analysis.
"""

import feedparser
import json
import os
import re
from datetime import datetime
import mysql.connector

rss_url = "https://feeds.washingtonpost.com/rss/business/technology"

database = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'news_db'
}

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
        article = {
            "title": entry.get("title"),
            "link": entry.get("link"),
            "published": entry.get("published"),
            # rss provided summary, not ai generated
            "summary": entry.get("summary")
        }
        articles.append(article)
    return articles

def get_today_news(articles):
    today_articles = []
    day = datetime.now().strftime("%a")

    for article in articles:
        date = article.get("published")
        if date.startswith(day):
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

    return f'''        <div class="col-md-6 col-lg-4 mb-4">
          <div class="card h-100" style="border: 1px solid #ddd; border-radius: 8px; overflow: hidden;">
            <div class="card-body">
              <span class="badge" style="background-color: #ffbe33; color: #fff; padding: 5px 10px; border-radius: 4px; font-size: 12px;">Technology</span>
              <h5 class="card-title mt-2" style="font-weight: bold; color: #222;">{title}</h5>
              <p class="card-text" style="color: #666; font-size: 14px;">{summary[:200] if summary else ""}...</p>
              <p style="color: #999; font-size: 12px;"><i class="fa fa-calendar"></i> {published}</p>
              <a href="{link}" target="_blank" class="btn" style="background-color: #222; color: #fff; padding: 8px 16px; border-radius: 4px; font-size: 14px;">Read More</a>
            </div>
          </div>
        </div>'''

def update_trend_html(articles):
    html_path = os.path.join(os.path.dirname(__file__), "..", "trend.html")

    with open(html_path, "r", encoding="utf-8") as f:
        html_content = f.read()

    cards_html = "\n".join([generate_article_card(article) for article in articles])

    pattern = r'(<div class="row" id="tech-news-container">).*?(</div>\s*</div>\s*</section>)'
    replacement = rf'\1\n{cards_html}\n      \2'

    new_html = re.sub(pattern, replacement, html_content, flags=re.DOTALL)

    with open(html_path, "w", encoding="utf-8") as f:
        f.write(new_html)

    print(f"Updated trend.html with {len(articles)} articles")

def setup_db(file='trend.sql'):
    server_config = {}
    for key, value in database.items():
        if key != 'database':
            server_config[key] = value
    
    conn = None
    cursor = None

    try:
        conn = mysql.connector.connect(**server_config)
        cursor = conn.cursor()

        with open(file, 'r') as f:
            sql_commands = f.read().split(';')

        for command in sql_commands:
            if command.strip():
                cursor.execute(command)
        conn.commit()
        print("Database and tables created successfully.")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if cursor: cursor.close()
        if conn: conn.close()

if __name__ == "__main__":
    already_ran_today = True
    if not already_ran_today:
        filename = get_filename()
        
        if not today_news_exists():
            news = fetch_tech_news()
            # print(f"fetched {len(news)} tech news articles.")

            save_to_json(news, filename)
            # print(f"saved to {filename}")
        
        articles = load_from_json(filename)

        unique_articles = remove_duplicates(articles)

        today_articles = get_today_news(articles)

        update_trend_html(unique_articles)

        setup_db()
