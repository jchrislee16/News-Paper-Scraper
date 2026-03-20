/**
 * Click Tracking for News Articles
 * Tracks which articles are clicked and sends data to tracking API
 */

 (function() {
    // Configuration - change this to your API endpoint
    const TRACK_API = 'http://20.151.118.114:5000/api/track';

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
(function() {
    function localTrackClick(link) {
        const url = link.href;
        let counts = JSON.parse(localStorage.getItem('clickCounts') || '{}');
        counts[url] = (counts[url] || 0) + 1;
        localStorage.setItem('clickCounts', JSON.stringify(counts));
        console.log(`Clicked: ${link.textContent.trim()} | Total: ${counts[url]}`);
    }

    function initLocalTracking() {
        document.querySelectorAll('a.track-click').forEach(link => {
            link.addEventListener('click', function(e) {
                localTrackClick(this);
            });
        });

        console.debug('Local click tracking initialized for',
            document.querySelectorAll('a.track-click').length, 'links');
        
        // Console output on page load
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

// run the command in the local console
// window.getClickCounts()