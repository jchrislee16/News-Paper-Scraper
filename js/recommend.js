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

    return newsList.map(news => {
        let topicKey = (news.category || 'Unknown').toLowerCase();
        if (topicKey === 'technology' || topicKey === 'tech') topicKey = 'tech';
        const sourceKey = news.source || 'Unknown';

        // 1. Retrieve news scores from user preference maps (defaults to 0 if not found)
        const tScore = topicScores[topicKey] || 0;
        const sScore = sourceScores[sourceKey] || 0;

        // 2. Calculate final score (e.g., 70% category weight, 30% news source weight)
        let finalScore = (tScore * 0.7) + (sScore * 0.3);

        // 3. Filtering logic: Significantly penalize scores for already read articles to push them to the end
        if (readArticles.includes(news.url)) {
            finalScore -= 2.0; 
        }

        return { ...news, recommendScore: finalScore };
    })
    // 4. Sort in descending order by recommendation score
    .sort((a, b) => b.recommendScore - a.recommendScore);
}

window.getRecommendedNews = getRecommendedNews;
