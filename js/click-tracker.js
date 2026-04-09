/**
 * Local Click Tracking for News Articles
 * Tracks click counts and client identification in localStorage for debugging.
 */
 (function() {

    // 1. Client ID Management
    function getOrCreateClientId() {
        let clientId = localStorage.getItem('track_client_id');
        if (!clientId || clientId === 'unknown_user') {
            clientId = 'user_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now();
            localStorage.setItem('track_client_id', clientId);
        }
        return clientId;
    }

    const clientId = getOrCreateClientId();

    // 2. Main Tracking Function
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
                // Extract date from text
                if (/\d{2,4}.*\d{2,4}/.test(p.innerText)) {
                    date = p.innerText.replace(/Score:.*/, '').trim();
                }
                // Extract Upvotes and Comments count
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

        // Manage localStorage data
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

        // Update tracking info
        counts[url].clicks += 1;
        counts[url].history.push({ 
            timestamp: timestamp,
            clientId: clientId 
        });

        localStorage.setItem('clickCounts', JSON.stringify(counts));
        console.log(`Clicked: ${title} | Total clicks: ${counts[url].clicks} | Client: ${clientId}`);
    }

    // 3. Initialize Tracking
    function initTracking() {
        console.log("test 2");
        const links = document.querySelectorAll('a.track-click');
        
        links.forEach(function(link) {
            link.addEventListener('click', function() {
                trackClick(this);
            });
        });

        console.debug('Local click tracking initialized for', links.length, 'links');
        console.log('✅ Trend.html page load complete on server');
    }

    // Check DOM readiness
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initTracking);
    } else {
        initTracking();
    }

    // Public helper to check counts in console
    window.getClickCounts = function() {
        return JSON.parse(localStorage.getItem('clickCounts') || '{}');
    };

})();