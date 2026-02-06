#!/usr/bin/env python3
"""
Minimal test server for GCloud VM.
Verifies: Flask serves JSON + CORS allows GitHub Pages to fetch it.

Usage:
  pip install flask flask-cors
  python3 test_server.py

Once MySQL is installed, set TEST_MYSQL=1 to test DB connection too:
  TEST_MYSQL=1 DB_PASSWORD=yourpass python3 test_server.py
"""

import os
from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)


@app.route('/api/test', methods=['GET'])
def test_endpoint():
    """Basic connectivity test - always works."""
    return jsonify({
        'success': True,
        'message': 'API is reachable!',
        'articles': [
            {
                'title': 'Test Article 1',
                'source': 'Test Source',
                'category': 'Technology',
                'url': 'https://example.com/1',
                'trending_score': 42
            },
            {
                'title': 'Test Article 2',
                'source': 'Test Source',
                'category': 'World',
                'url': 'https://example.com/2',
                'trending_score': 17
            }
        ]
    })


@app.route('/api/test/db', methods=['GET'])
def test_db():
    """MySQL connectivity test - only works when MySQL is set up."""
    try:
        import mysql.connector
        conn = mysql.connector.connect(
            host=os.environ.get('DB_HOST', 'localhost'),
            user=os.environ.get('DB_USER', 'root'),
            password=os.environ.get('DB_PASSWORD', ''),
            database=os.environ.get('DB_NAME', 'news_db')
        )
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT COUNT(*) AS count FROM articles")
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        return jsonify({
            'success': True,
            'message': 'Database connected!',
            'article_count': row['count']
        })
    except ImportError:
        return jsonify({
            'success': False,
            'message': 'mysql-connector-python not installed. Run: pip install mysql-connector-python'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'DB error: {e}'
        }), 500


if __name__ == '__main__':
    print("Test Server")
    print("=" * 40)
    print("  GET /api/test    - Basic connectivity")
    print("  GET /api/test/db - MySQL connectivity")
    print("=" * 40)
    app.run(host='0.0.0.0', port=5000)
