(function() {
    const TRACK_API = 'http://20.151.118.114:5000/api/track';

    function getOrCreateClientId() {
        let clientId = localStorage.getItem('track_client_id');
        if (!clientId || clientId === 'unknown_user') {
            clientId = 'user_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now();
            localStorage.setItem('track_client_id', clientId);
        }
        return clientId;
    }

    const clientId = getOrCreateClientId();

    function trackClick(link) {
        console.log("test"); 
        const url = link.href;

        const cardBody = link.closest('.card-body');
        const title = link.dataset.title || (cardBody?.querySelector('h5.card-title')?.innerText.trim() || 'No Title');

        let date = '';
        let upvotes = 0;
        let comments = 0;

        if (cardBody) {
            const pTags = cardBody.querySelectorAll('p');
            for (let p of pTags) {
                if (/\d{2,4}.*\d{2,4}/.test(p.innerText)) {
                    date = p.innerText.replace(/Score:.*/,'').trim();
                }
                if (p.innerText.includes('Upvotes') && p.innerText.includes('Comments')) {
                    const match = p.innerText.match(/Upvotes:\s*([\d,]+)\s*\|\s*Comments:\s*([\d,]+)/);
                    if (match) {
                        upvotes = parseInt(match[1].replace(/,/g,''), 10);
                        comments = parseInt(match[2].replace(/,/g,''), 10);
                    }
                }
            }
        }

        const timestamp = new Date().toISOString();

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

        console.log(`Clicked: ${title} | Total clicks: ${counts[url].clicks}`);

        const payload = {
            clientId: clientId, 
            url: url,
            title: title,
            source: link.dataset.source || 'Unknown',
            category: link.dataset.category || 'Unknown'
        };

        fetch(TRACK_API, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
            keepalive: true 
        }).catch(err => console.debug('Azure send failed:', err));
    }

    function initLocalTracking() {
        // Using Event Delegation to handle dynamically loaded content
        document.addEventListener('click', function(event) {
            const link = event.target.closest('a.track-click');
            if (link) {
                trackClick(link);
            }
        });
        console.log("Global tracking initialized");
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initLocalTracking);
    } else {
        initLocalTracking();
    }

    window.getClickCounts = function() {
        return JSON.parse(localStorage.getItem('clickCounts') || '{}');
    };
})();