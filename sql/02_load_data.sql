-- =====================================================================
-- YouTube Video Sharing Database: Phase 2 Data Loading
-- Deliverable: sql/02_load_data.sql (Checkpoint 1)
--
-- Loads all 10 seed CSV files in topological order (parents before children),
-- runs ANALYZE to update statistics, verifies row counts, and tests integrity.
-- =====================================================================

SET search_path TO youtube;

-- 1. LOAD DATA IN PARENT-BEFORE-CHILD ORDER
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);
\copy channels FROM 'seed_data/channels.csv' WITH (FORMAT csv, HEADER true);
\copy videos FROM 'seed_data/videos.csv' WITH (FORMAT csv, HEADER true);
\copy playlists FROM 'seed_data/playlists.csv' WITH (FORMAT csv, HEADER true);
\copy subscriptions FROM 'seed_data/subscriptions.csv' WITH (FORMAT csv, HEADER true);
\copy watch_events FROM 'seed_data/watch_events.csv' WITH (FORMAT csv, HEADER true);
\copy video_reactions FROM 'seed_data/video_reactions.csv' WITH (FORMAT csv, HEADER true);
\copy comments FROM 'seed_data/comments.csv' WITH (FORMAT csv, HEADER true);
\copy playlist_items FROM 'seed_data/playlist_items.csv' WITH (FORMAT csv, HEADER true);
\copy ad_impressions FROM 'seed_data/ad_impressions.csv' WITH (FORMAT csv, HEADER true);

-- 2. REFRESH PLANNER STATISTICS
ANALYZE;

-- 3. ROW COUNT VERIFICATION
-- Check that loaded row count matches each seed CSV export exactly.
SELECT 'users' AS table_name, count(*) AS loaded_rows, 30000 AS expected_rows FROM users
UNION ALL
SELECT 'channels', count(*), 3000 FROM channels
UNION ALL
SELECT 'videos', count(*), 30000 FROM videos
UNION ALL
SELECT 'playlists', count(*), 8000 FROM playlists
UNION ALL
SELECT 'subscriptions', count(*), 129253 FROM subscriptions
UNION ALL
SELECT 'watch_events', count(*), 200000 FROM watch_events
UNION ALL
SELECT 'video_reactions', count(*), 67417 FROM video_reactions
UNION ALL
SELECT 'comments', count(*), 60000 FROM comments
UNION ALL
SELECT 'playlist_items', count(*), 56005 FROM playlist_items
UNION ALL
SELECT 'ad_impressions', count(*), 57014 FROM ad_impressions;


-- 4. INTEGRITY CHECKS (Must all return 0 violations)
-- Integrity Check 1: Watch duration never exceeds video duration
SELECT count(*) AS violations_watch_longer_than_video
FROM watch_events w
JOIN videos v ON w.video_id = v.video_id
WHERE w.watch_seconds > v.duration_sec;

-- Integrity Check 2: Nobody watched a video before it was uploaded
SELECT count(*) AS violations_watch_before_upload
FROM watch_events w
JOIN videos v ON w.video_id = v.video_id
WHERE w.started_at < v.uploaded_at;

-- Integrity Check 3: A playlist does not contain the same video twice
SELECT count(*) AS violations_duplicate_playlist_videos
FROM (
    SELECT playlist_id, video_id
    FROM playlist_items
    GROUP BY playlist_id, video_id
    HAVING count(*) > 1
) dupes;