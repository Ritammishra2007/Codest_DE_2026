-- =====================================================================
-- YouTube Video Sharing Database: Query Optimization Indexes
-- File: sql/05_indexes.sql
--
-- Contains all secondary indexes added to accelerate the workload.
-- Each index is justified with query targets, index type, and column order.
-- =====================================================================

SET search_path TO youtube, public;

-- Enable Trigram extension for case-insensitive substring search
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public;

-- ---------------------------------------------------------------------
-- 1. VIDEOS TABLE INDEXES
-- ---------------------------------------------------------------------

-- Index 1: Serves R01 (Channel page 20 newest videos) and R03 (Subscriptions feed)
-- Type: Partial Composite B-tree
-- Column Order: channel_id (equality filter) -> published_at DESC (sort order)
-- Partial Filter: WHERE visibility = 'PUBLIC'
-- Justification: Filters directly for public videos of a channel and provides
-- pre-sorted rows without requiring an in-memory sort or table scan.
CREATE INDEX IF NOT EXISTS idx_videos_channel_public 
ON videos (channel_id, published_at DESC) 
WHERE visibility = 'PUBLIC';

-- Index 2: Serves R04 (Title search with ILIKE '%tutorial%')
-- Type: GIN Trigram Index
-- Justification: Standard B-tree indexes cannot accelerate leading wildcards (%text%).
-- A GIN trigram index splits text into 3-character trigrams, transforming
-- an expensive sequential scan over 30,000 titles into a fast bitmap index scan.
CREATE INDEX IF NOT EXISTS idx_videos_title_trgm 
ON videos USING gin (title public.gin_trgm_ops) 
WHERE visibility = 'PUBLIC';

-- Index 3: Serves R06 (Publishing queue) and W05 (Scheduled video updates)
-- Type: Partial B-tree
-- Justification: Out of 30,000 videos, only ~60 are scheduled at any given time.
-- A partial index indexes only scheduled videos, keeping index size tiny (<16 KB)
-- and imposing zero write overhead on regular video uploads.
CREATE INDEX IF NOT EXISTS idx_videos_scheduled 
ON videos (published_at) 
WHERE visibility = 'SCHEDULED';

-- Index 4: Serves R10 (Shorts shelf top viewed)
-- Type: Partial B-tree
-- Justification: Filters exclusively for short-form content (is_short = true).
CREATE INDEX IF NOT EXISTS idx_videos_is_short 
ON videos (video_id) 
WHERE is_short = TRUE;

-- ---------------------------------------------------------------------
-- 2. WATCH EVENTS TABLE INDEXES
-- ---------------------------------------------------------------------

-- Index 5: Serves R05 (User watch history: last 50 watched videos)
-- Type: Composite B-tree
-- Column Order: user_id (equality) -> started_at DESC (sort order)
-- Justification: Directly locates views for a specific user and returns them
-- in reverse chronological order without sorting 200,000 records.
CREATE INDEX IF NOT EXISTS idx_watch_events_user_started 
ON watch_events (user_id, started_at DESC);

-- Index 6: Serves R07, R08, R09, R13, R17, R19 (Foreign key lookups on video_id)
-- Type: Single-column B-tree
-- Justification: Foreign keys are not automatically indexed by PostgreSQL.
-- Indexing video_id avoids repeated 200,000-row sequential scans when joining
-- videos with watch events.
CREATE INDEX IF NOT EXISTS idx_watch_events_video_id 
ON watch_events (video_id);

-- Index 7: Serves R10, R11, R16, R20 (Time-range aggregations in June 2026)
-- Type: Single-column B-tree
-- Justification: Accelerates range scans on playback timestamps (started_at >= ...).
CREATE INDEX IF NOT EXISTS idx_watch_events_started_at 
ON watch_events (started_at);

-- ---------------------------------------------------------------------
-- 3. COMMENTS TABLE INDEXES
-- ---------------------------------------------------------------------

-- Index 8: Serves R15 (Watch page top and pinned comments)
-- Type: Partial Composite B-tree
-- Column Order: video_id (equality) -> is_pinned DESC -> like_count DESC
-- Partial Filter: WHERE parent_comment_id IS NULL
-- Justification: Only top-level comments are displayed on the main watch page.
-- This partial index skips replies and provides the exact sorting order needed.
CREATE INDEX IF NOT EXISTS idx_comments_video_pinned 
ON comments (video_id, is_pinned DESC, like_count DESC) 
WHERE parent_comment_id IS NULL;

-- Index 9: Serves R23 (Comment moderation queue pagination)
-- Type: Single-column B-tree
-- Column Order: created_at DESC
-- Justification: Allows the moderation queue query to scan comments in reverse
-- chronological order using an index scan instead of an in-memory sort.
CREATE INDEX IF NOT EXISTS idx_comments_created_at 
ON comments (created_at DESC);

-- Index 10: Serves R18 (Child safety check for comments on kids videos)
-- Type: Single-column B-tree
-- Justification: Allows fast semi-join / EXISTS lookups to check if comments exist.
CREATE INDEX IF NOT EXISTS idx_comments_video_id 
ON comments (video_id);

-- ---------------------------------------------------------------------
-- 4. SUBSCRIPTIONS & ENGAGEMENT INDEXES
-- ---------------------------------------------------------------------

-- Index 11: Serves R13, R24, W04 (Channel-specific subscriber lookups)
-- Type: Single-column B-tree
-- Justification: The primary key is (user_id, channel_id). Queries filtering
-- by channel_id alone cannot use the leading column of the primary key.
CREATE INDEX IF NOT EXISTS idx_subscriptions_channel_id 
ON subscriptions (channel_id);

-- Index 12: Serves R14 (Studio likes/dislikes aggregate per video)
-- Type: Single-column B-tree
-- Justification: The primary key on video_reactions is (user_id, video_id).
-- An index on video_id allows fast grouping of reactions per video.
CREATE INDEX IF NOT EXISTS idx_video_reactions_video_id 
ON video_reactions (video_id);

-- ---------------------------------------------------------------------
-- 5. ADVERTISING & MONETIZATION INDEXES
-- ---------------------------------------------------------------------

-- Index 13: Serves R16, R25 (Ad impressions time-range filters)
-- Type: Single-column B-tree
-- Justification: Accelerates date-bounded joins on ad impressions.
CREATE INDEX IF NOT EXISTS idx_ad_impressions_shown_at 
ON ad_impressions (shown_at);

-- Index 14: Serves R25 (Premium ad-serving compliance audit)
-- Type: Partial B-tree
-- Justification: Only ~2,400 out of 30,000 users have an active Premium membership.
-- A partial index ignores free users and indexes only active premium expiration dates.
CREATE INDEX IF NOT EXISTS idx_users_premium_until 
ON users (premium_until) 
WHERE premium_until IS NOT NULL;

-- Refresh optimizer statistics
ANALYZE;