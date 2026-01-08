#!/usr/bin/env python3
"""
Simple Click Tracking Server
Run with: python3 api/track_server.py
Then access at http://localhost:5000
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import json
import os
from datetime import datetime
import hashlib

app = Flask(__name__)
CORS(app)

DATA_FILE = os.path.join(os.path.dirname(__file__), 'clicks.json')


def load_clicks():
    """Load click data from JSON file."""
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE, 'r') as f:
            return json.load(f)
    return {}


def save_clicks(data):
    """Save click data to JSON file."""
    with open(DATA_FILE, 'w') as f:
        json.dump(data, f, indent=2)


@app.route('/api/track', methods=['GET'])
def get_stats():
    """Get click statistics."""
    clicks = load_clicks()

    # Sort by count descending
    sorted_clicks = dict(sorted(
        clicks.items(),
        key=lambda x: x[1].get('count', 0),
        reverse=True
    ))

    total = sum(item.get('count', 0) for item in clicks.values())

    return jsonify({
        'success': True,
        'total_clicks': total,
        'unique_articles': len(clicks),
        'articles': sorted_clicks
    })


@app.route('/api/track', methods=['POST'])
def track_click():
    """Record a click event."""
    data = request.get_json()

    if not data or 'url' not in data or 'title' not in data:
        return jsonify({'error': 'Missing url or title'}), 400

    url = data['url']
    title = data['title']
    category = data.get('category', 'Unknown')
    source = data.get('source', 'Unknown')

    clicks = load_clicks()

    # Use URL hash as key
    key = hashlib.md5(url.encode()).hexdigest()

    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    if key in clicks:
        clicks[key]['count'] += 1
        clicks[key]['last_clicked'] = now
    else:
        clicks[key] = {
            'url': url,
            'title': title,
            'category': category,
            'source': source,
            'count': 1,
            'first_clicked': now,
            'last_clicked': now
        }

    save_clicks(clicks)

    return jsonify({
        'success': True,
        'total_clicks': clicks[key]['count']
    })


@app.route('/api/stats/category', methods=['GET'])
def category_stats():
    """Get click stats grouped by category."""
    clicks = load_clicks()

    categories = {}
    for item in clicks.values():
        cat = item.get('category', 'Unknown')
        if cat not in categories:
            categories[cat] = {'count': 0, 'articles': 0}
        categories[cat]['count'] += item.get('count', 0)
        categories[cat]['articles'] += 1

    return jsonify({
        'success': True,
        'categories': dict(sorted(
            categories.items(),
            key=lambda x: x[1]['count'],
            reverse=True
        ))
    })


@app.route('/api/stats/source', methods=['GET'])
def source_stats():
    """Get click stats grouped by source."""
    clicks = load_clicks()

    sources = {}
    for item in clicks.values():
        src = item.get('source', 'Unknown')
        if src not in sources:
            sources[src] = {'count': 0, 'articles': 0}
        sources[src]['count'] += item.get('count', 0)
        sources[src]['articles'] += 1

    return jsonify({
        'success': True,
        'sources': dict(sorted(
            sources.items(),
            key=lambda x: x[1]['count'],
            reverse=True
        ))
    })


if __name__ == '__main__':
    print("Click Tracking Server")
    print("=" * 40)
    print("Endpoints:")
    print("  POST /api/track     - Record a click")
    print("  GET  /api/track     - Get all stats")
    print("  GET  /api/stats/category - Stats by category")
    print("  GET  /api/stats/source   - Stats by source")
    print("=" * 40)
    app.run(host='0.0.0.0', port=5000, debug=True)
