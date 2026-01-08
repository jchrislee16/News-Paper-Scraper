<?php
/**
 * Simple Click Tracking API
 * Logs article clicks to a JSON file
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

$data_file = __DIR__ . '/clicks.json';

// Load existing data
function load_clicks($file) {
    if (file_exists($file)) {
        $content = file_get_contents($file);
        return json_decode($content, true) ?: [];
    }
    return [];
}

// Save data
function save_clicks($file, $data) {
    file_put_contents($file, json_encode($data, JSON_PRETTY_PRINT));
}

// GET - Return click stats
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $clicks = load_clicks($data_file);

    // Sort by count descending
    uasort($clicks, function($a, $b) {
        return $b['count'] - $a['count'];
    });

    echo json_encode([
        'success' => true,
        'total_clicks' => array_sum(array_column($clicks, 'count')),
        'unique_articles' => count($clicks),
        'articles' => $clicks
    ]);
    exit;
}

// POST - Record a click
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);

    if (!isset($input['url']) || !isset($input['title'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing url or title']);
        exit;
    }

    $url = $input['url'];
    $title = $input['title'];
    $category = $input['category'] ?? 'Unknown';
    $source = $input['source'] ?? 'Unknown';

    $clicks = load_clicks($data_file);

    // Use URL as key (normalized)
    $key = md5($url);

    if (isset($clicks[$key])) {
        $clicks[$key]['count']++;
        $clicks[$key]['last_clicked'] = date('Y-m-d H:i:s');
    } else {
        $clicks[$key] = [
            'url' => $url,
            'title' => $title,
            'category' => $category,
            'source' => $source,
            'count' => 1,
            'first_clicked' => date('Y-m-d H:i:s'),
            'last_clicked' => date('Y-m-d H:i:s')
        ];
    }

    save_clicks($data_file, $clicks);

    echo json_encode([
        'success' => true,
        'total_clicks' => $clicks[$key]['count']
    ]);
    exit;
}

http_response_code(405);
echo json_encode(['error' => 'Method not allowed']);
