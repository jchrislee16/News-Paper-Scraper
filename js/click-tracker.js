/**
 * Local Click Tracking for News Articles
 * Tracks click counts in localStorage for debugging.
 * Main preference tracking is handled by user-prefs.js.
 */
(function() {
    function trackClick(link) {
        console.log("test");
        const url = link.href;
        console.log(url);

        const cardBody = link.closest('.card-body');
        const title = link.dataset.title || (cardBody?.querySelector('h5.card-title')?.innerText.trim() || 'No Title');

        let date = '';
        if (cardBody) {
            const pTags = cardBody.querySelectorAll('p');
            for (let p of pTags) {
                if (/\d{2,4}.*\d{2,4}/.test(p.innerText)) {
                    date = p.innerText.replace(/Score:.*/,'').trim();
                }
                if (p.innerText.includes('Upvotes') && p.innerText.includes('Comments')) {
                    const match = p.innerText.match(/Upvotes:\s*([\d,]+)\s*\|\s*Comments:\s*([\d,]+)/);
                    if (match) {
                        var upvotes = parseInt(match[1].replace(/,/g,''), 10);
                        var comments = parseInt(match[2].replace(/,/g,''), 10);
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
    }

    function initLocalTracking() {
        console.log("test 2");
        document.querySelectorAll('a.track-click').forEach(link => {
            link.addEventListener('click', function() {
                trackClick(this);
            });
        });

        console.debug('Local click tracking initialized for',
            document.querySelectorAll('a.track-click').length, 'links');
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
