/**
 * Local Click Tracking for News Articles
 * Tracks click counts in localStorage for debugging with a 100-item history limit
 * and implements a 5% dynamic weight allocation vector logic for user preference.
 * Main preference tracking is handled by user-prefs.js or this fallback.
 */
 (function() {
    /**
     * Handles the click event on news article links, safely saves tracking data 
     * to localStorage, triggers user-prefs tracking, and then opens the link.
     * @param {Event} event - The click event object
     * @param {HTMLAnchorElement} link - The clicked anchor element
     */
    function localTrackClick(event, link) {
        console.log("clicked");
        
        if (event) {
            event.preventDefault();
        }

        const url = link.href;
        const cardBody = link.closest('.card-body');
        const card = link.closest('.col-md-6, .col-lg-4, .card'); 
        const title = link.dataset.title || (cardBody?.querySelector('h5.card-title')?.innerText.trim() || 'No Title');
        const source = link.dataset.source || 'Unknown';

        let category = 'Unknown';
        
        if (link.dataset.category && link.dataset.category !== 'Unknown') {
            category = link.dataset.category;
        } else if (card) {
            const badges = card.querySelectorAll('.badge');
            if (badges.length >= 3) {
                category = badges[2].textContent.trim();
            } else if (badges.length > 0) {
                category = badges[badges.length - 1].textContent.trim();
            }
        }

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
                category: category, 
                date: date,
                upvotes: upvotes || 0,
                comments: comments || 0,
                clicks: 0,
                history: []
            };
        } else {
            counts[url].category = category;
        }

        counts[url].clicks += 1;
        counts[url].history.push({ timestamp });

        const newsCount = Object.keys(counts).length;
        const limit = 100;
        if (newsCount > limit) {
            const keys = Object.keys(counts);
            const oldData = newsCount - limit;
            for (let i = 0; i < oldData; i++) {
                delete counts[keys[i]];
            }
        }

        localStorage.setItem('clickCounts', JSON.stringify(counts));
        console.log(`Saved clickCounts with Category: ${category}`);

        if (typeof window.recordClick === 'function') {
            window.recordClick(url, category, source);
        } else {
            try {
                let prefs = JSON.parse(localStorage.getItem('newsUserPrefs') || '{}');
                prefs.readArticles = prefs.readArticles || [];
                prefs.topicScores = prefs.topicScores || {};
                prefs.sourceScores = prefs.sourceScores || {};

                if (prefs.readArticles.indexOf(url) === -1) {
                    prefs.readArticles.push(url);
                }
                if (prefs.readArticles.length > 100) {
                    prefs.readArticles.shift();
                }
                
                let topicKey = category.toLowerCase();
                if (category === 'Technology' || category === 'Tech') topicKey = 'tech';

                let totalTopicScore = Object.values(prefs.topicScores).reduce((a, b) => a + b, 0);
                
                if (totalTopicScore === 0) {
                    prefs.topicScores[topicKey] = 1.0;
                } else {
                    Object.keys(prefs.topicScores).forEach(key => {
                        prefs.topicScores[key] = (prefs.topicScores[key] / totalTopicScore) * 0.95;
                    });
                    prefs.topicScores[topicKey] = (prefs.topicScores[topicKey] || 0) + 0.05;
                }

                if (source) {
                    let totalSourceScore = Object.values(prefs.sourceScores).reduce((a, b) => a + b, 0);
                    if (totalSourceScore === 0) {
                        prefs.sourceScores[source] = 1.0;
                    } else {
                        Object.keys(prefs.sourceScores).forEach(key => {
                            prefs.sourceScores[key] = (prefs.sourceScores[key] / totalSourceScore) * 0.95;
                        });
                        prefs.sourceScores[source] = (prefs.sourceScores[source] || 0) + 0.05;
                    }
                }

                localStorage.setItem('newsUserPrefs', JSON.stringify(prefs));
            } catch (e) {
                console.error("Failed to fallback sync user-prefs", e);
            }
        }

        setTimeout(function() {
            const target = link.target || '_self';
            window.open(url, target);
        }, 100);
    }

    function initLocalTracking() {
        document.querySelectorAll('a.track-click').forEach(link => {
            if (!link.dataset.trackerInitialized) {
                link.dataset.trackerInitialized = 'true';
                link.addEventListener('click', function(e) {
                    localTrackClick(e, this);
                });
            }
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

    window.reinitClickTracking = initLocalTracking;
})();
