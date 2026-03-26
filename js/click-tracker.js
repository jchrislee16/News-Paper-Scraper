/**
 * Click Tracking for News Articles
 * Tracks which articles are clicked and sends data to tracking API
 */

 (function() {
    // Configuration - change this to your API endpoint
    const TRACK_API = 'https://undefined-arena-page-horn.trycloudflare.com/api/track';

    // Track click function
    function trackClick(linkElement) {
        const data = {
            url: linkElement.href,
            title: linkElement.dataset.title || 'Unknown',
            source: linkElement.dataset.source || 'Unknown',
            category: linkElement.dataset.category || 'Unknown',
            timestamp: new Date().toISOString()
        };

        // Send tracking data (fire and forget)
        fetch(TRACK_API, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data),
            // Use keepalive to ensure request completes even if page navigates
            keepalive: true
        }).catch(function(err) {
            // Silently fail - don't block user
            console.debug('Track failed:', err);
        });
    }

    // Attach click handlers to all tracked links
    function initTracking() {
        document.querySelectorAll('a.track-click').forEach(function(link) {
            link.addEventListener('click', function(e) {
                trackClick(this);
                // Don't prevent default - let the link work normally
            });
        });

        console.debug('Click tracking initialized for',
            document.querySelectorAll('a.track-click').length, 'links');

        // Console output on page load
        console.log('✅ Trend.html page load complete on server');

    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initTracking);
    } else {
        initTracking();
    }
})();

// Local click tracking
// localStorage.removeItem('clickCounts');

(function() {
    function localTrackClick(link) {
        const url = link.href;

        const cardBody = link.closest('.card-body');
        const title = link.dataset.title || (cardBody?.querySelector('h5.card-title')?.innerText.trim() || 'No Title');

        let date = '';
        if (cardBody) {
            const pTags = cardBody.querySelectorAll('p');
            for (let p of pTags) {
                // 날짜 찾기: 숫자가 포함된 텍스트
                if (/\d{2,4}.*\d{2,4}/.test(p.innerText)) {
                    date = p.innerText.replace(/Score:.*/,'').trim();
                }
                // 업보트, 코멘트 찾기: "Upvotes: 123 | Comments: 456"
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
        document.querySelectorAll('a.track-click').forEach(link => {
            link.addEventListener('click', function() {
                localTrackClick(this);
            });
        });

        console.debug('Local click tracking initialized for', document.querySelectorAll('a.track-click').length, 'links');
        console.log('✅ Trend.html page load complete on local');
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

// (function() {
//     function localTrackClick(link) {
//         const url = link.href;
//         let counts = JSON.parse(localStorage.getItem('clickCounts') || '{}');
//         counts[url] = (counts[url] || 0) + 1;
//         localStorage.setItem('clickCounts', JSON.stringify(counts));
//         console.log(`Clicked: ${link.textContent.trim()} | Total: ${counts[url]}`);
//     }

//     function initLocalTracking() {
//         document.querySelectorAll('a.track-click').forEach(link => {
//             link.addEventListener('click', function(e) {
//                 localTrackClick(this);
//             });
//         });

//         console.debug('Local click tracking initialized for',
//             document.querySelectorAll('a.track-click').length, 'links');
        
//         // Console output on page load
//         console.log('✅ Trend.html page load complete on local');
//     }

//     if (document.readyState === 'loading') {
//         document.addEventListener('DOMContentLoaded', initLocalTracking);
//     } else {
//         initLocalTracking();
//     }

//     window.getClickCounts = function() {
//         return JSON.parse(localStorage.getItem('clickCounts') || '{}');
//     };
// })();

// run the command in the local console
// window.getClickCounts()