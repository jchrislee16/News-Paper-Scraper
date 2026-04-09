/**
 * Click Tracking for News Articles
 * Tracks click counts in localStorage and sends data to tracking API.
 */
 (function() {

    function getOrCreateClientId() {
        let clientId = localStorage.getItem('track_client_id');
        if (!clientId || clientId === 'unknown_user') {
            clientId = 'user_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now();
            localStorage.setItem('track_client_id', clientId);
        }
        return clientId;
    }

    const clientId = getOrCreateClientId();
    const TRACK_API = 'YOUR_API_URL_HERE';

    function trackClick(link) {
        console.log("test");
        const url = link.href;
        console.log(url);

        const cardBody = link.closest('.card-body');
        const title = link.dataset.title || (cardBody?.querySelector('h5.card-title')?.innerText.trim() || 'No Title');

        let date = '';
        let upvotes = 0;
        let comments = 0;

        if (cardBody) {
            const pTags = cardBody.querySelectorAll('p');
            for (let p of pTags) {
                if (/\d{2,4}.*\d{2,4}/.test(p.innerText)) {
                    date = p.innerText.replace(/Score:.*/, '').trim();
                }
                if (p.innerText.includes('Upvotes') && p.innerText.includes('Comments')) {
                    const match = p.innerText.match(/Upvotes:\s*([\d,]+)\s*\|\s*Comments:\s*([\d,]+)/);
                    if (match) {
                        upvotes = parseInt(match[1].replace(/,/g, ''), 10);
                        comments = parseInt(match[2].replace(/,/g, ''), 10);
                    }
                }
            }
        }

        const timestamp = new Date().toISOString();

        // Local storage tracking
        let counts = {};
        try {
            counts = JSON.parse(localStorage.getItem('clickCounts') || '{}');
            if (typeof counts !== 'object' || counts === null) counts = {};
        } catch (e) {
            counts = {};
        }

        if (!counts[url] || typeof counts[url] !== 'object') {
            counts[url] = {
                url: url,
                title: title,
                date: date,
                upvotes: upvotes || 0,
                comments: comments || 0,
                clicks: 0,
                history: []
            };
        }

        counts[url].clicks += 1;
        counts[url].history.push({ timestamp });
        localStorage.setItem('clickCounts', JSON.stringify(counts));

        // API tracking data
        const data = {
            clientId: clientId,
            url: url,
            title: title,
            source: link.dataset.source || 'Unknown',
            category: link.dataset.category || 'Unknown',
            timestamp: timestamp
        };

        // Send tracking data (fire and forget)
        fetch(TRACK_API, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data),
            keepalive: true
        }).catch(function(err) {
            console.debug('Track failed:', err);
        });

        console.log(`Clicked: ${title} | Total clicks: ${counts[url].clicks}`);
    }

    function initTracking() {
        console.log("test 2");
        const links = document.querySelectorAll('a.track-click');
        
        links.forEach(function(link) {
            link.addEventListener('click', function() {
                trackClick(this);
            });
        });

        console.debug('Click tracking initialized for', links.length, 'links');
        console.log('✅ Trend.html page load complete on server');
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initTracking);
    } else {
        initTracking();
    }

    window.getClickCounts = function() {
        return JSON.parse(localStorage.getItem('clickCounts') || '{}');
    };
})();