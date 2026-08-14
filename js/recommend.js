/**
 * Recommendation algorithm that sorts news articles based on accumulated user preference weights.
 * @param {Array} newsList - Original array of news articles fetched from the server or API
 * @returns {Array} News array sorted according to user preferences
 */
 function getRecommendedNews(newsList) {
    const prefs = JSON.parse(localStorage.getItem('newsUserPrefs') || '{}');
    const topicScores = prefs.topicScores || {};
    const sourceScores = prefs.sourceScores || {};
    const readArticles = prefs.readArticles || [];
    const readTitles = prefs.readTitles || [];

    const stopWords = new Set(['the', 'is', 'at', 'which', 'and', 'a', 'an', 'in', 'to', 'of', 'for']);

    return newsList.map(news => {
        let topicKey = (news.category || 'Unknown').toLowerCase();
        if (topicKey === 'technology' || topicKey === 'tech') topicKey = 'tech';
        const sourceKey = news.source || 'Unknown';

        const tScore = topicScores[topicKey] || 0;
        const sScore = sourceScores[sourceKey] || 0;

        let titleScore = 0;
        if (news.title && readTitles.length > 0) {
            const newsWords = news.title.toLowerCase()
                .replace(/[^\w\s]/gi, '')
                .split(/\s+/)
                .filter(w => w.length > 2 && !stopWords.has(w));

            readTitles.forEach(pastTitle => {
                const pastWords = new Set(
                    pastTitle.toLowerCase().replace(/[^\w\s]/gi, '').split(/\s+/)
                );
                newsWords.forEach(word => {
                    if (pastWords.has(word)) {
                        titleScore += 0.1;
                    }
                });
            });
        }

        let finalScore = (tScore * 0.5) + (sScore * 0.3) + (Math.min(titleScore, 1.0) * 0.2);

        if (readArticles.includes(news.url)) {
            finalScore -= 2.0; 
        }

        return { ...news, recommendScore: finalScore };
    })
    .sort((a, b) => b.recommendScore - a.recommendScore);
}

window.getRecommendedNews = getRecommendedNews;