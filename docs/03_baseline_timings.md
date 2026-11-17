# Phase 3: Baseline Timings & Query Execution Analysis

**Course:** DBMS Project · **Team:** T0006 · **Section:** D  
**File:** `docs/03_baseline_timings.md`

---

## 1. Benchmark Methodology

All 30 workload queries from `queries/workload_30.sql` (25 read queries `R01`–`R25` and 5 write queries `W01`–`W05`) were benchmarked against PostgreSQL 18.4 running on macOS (MacBook Pro M4).

- **Execution:** Each query was run **3 consecutive times** using `EXPLAIN (ANALYZE, BUFFERS)`.
- **Database State:** Measured against the unindexed baseline schema (`sql/01_schema.sql` with only default Primary Key and Unique b-tree indexes) populated with all 540,689 rows from `seed_data/` after running `ANALYZE;`.
- **Write Safety:** Write queries (`W01`–`W05`) were executed inside transactional `BEGIN; ... ROLLBACK;` blocks to ensure identical underlying data across all runs.
- **Plan Storage:** Complete raw execution plans for all 3 runs are saved in `benchmarks/results/baseline/` (`R01.txt` through `W05.txt`), and summary metrics are recorded in `benchmarks/results/baseline/summary.csv`.

---

## 2. Baseline Timing Table (All 30 Queries)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|:---:|---:|---:|---:|---:|
| **R01**: Channel page: the 20 newest public videos of channel 217 | READ | 3.156 | 2.338 | 2.522 | 2.672 |
| **R02**: Watch page: one video with its channel | READ | 0.060 | 0.055 | 0.074 | 0.063 |
| **R03**: Subscriptions feed: public videos from channels user 1042 subscribes to, newest first | READ | 3.573 | 3.240 | 3.044 | 3.286 |
| **R04**: Search: public videos with "tutorial" in the title, most viewed first | READ | 12.264 | 11.340 | 11.208 | 11.604 |
| **R05**: History page: the last 50 videos user 1042 watched | READ | 4.451 | 4.173 | 4.171 | 4.265 |
| **R06**: Publishing service: videos scheduled to go live in the first week of July 2026 | READ | 1.717 | 1.686 | 1.803 | 1.735 |
| **R07**: YouTube Studio: channel 217's daily views and watch hours in June 2026 | READ | 9.062 | 8.418 | 8.268 | 8.583 |
| **R08**: YouTube Studio: where views of video ZkNSlUB1EOs come from | READ | 5.083 | 4.886 | 5.950 | 5.306 |
| **R09**: YouTube Studio: average percentage watched for each of channel 217's videos | READ | 8.212 | 7.993 | 8.057 | 8.087 |
| **R10**: Shorts shelf: most viewed Shorts in the last 7 days of June 2026 | READ | 8.001 | 8.491 | 7.926 | 8.139 |
| **R11**: Trending tab: top 5 videos per category by views in June 2026 | READ | 14.886 | 14.309 | 14.412 | 14.536 |
| **R12**: Growth: share of logged-out viewing per device type | READ | 11.580 | 11.844 | 12.492 | 11.972 |
| **R13**: Creator insights: subscribers of channel 217 who have never watched any of its videos | READ | 13.584 | 12.918 | 13.167 | 13.223 |
| **R14**: YouTube Studio: likes, dislikes and like ratio per video of channel 217 | READ | 8.511 | 8.143 | 8.514 | 8.389 |
| **R15**: Watch page: pinned comment and top 10 comments of video ZkNSlUB1EOs | READ | 2.106 | 2.174 | 1.943 | 2.074 |
| **R16**: Finance: ad revenue per channel in June 2026, top 20 | READ | 12.574 | 11.537 | 28.404 | 17.505 |
| **R17**: Partner program: NOT_ELIGIBLE channels that now have 100+ subscribers and 40+ watch hours | READ | 13.234 | 13.466 | 13.752 | 13.484 |
| **R18**: Child safety: "made for kids" videos that still have comments (comments must be disabled) | READ | 8.907 | 8.779 | 8.634 | 8.773 |
| **R19**: Partner report: for every monetized channel, its latest upload and its total views | READ | 12073.274 | 12232.981 | 12579.006 | 12295.087 |
| **R20**: Platform analytics: daily watch hours and running total for June 2026 | READ | 8.687 | 8.412 | 8.504 | 8.534 |
| **R21**: Playlist page: playlist 501 in order | READ | 0.067 | 0.064 | 0.062 | 0.064 |
| **R22**: Copyright team: same title and duration uploaded by more than one channel | READ | 20.508 | 19.727 | 21.099 | 20.445 |
| **R23**: Moderation queue: all comments, newest first, page 1,201 (25 per page) | READ | 13.181 | 13.233 | 13.508 | 13.307 |
| **R24**: YouTube Studio: new subscribers per month for channel 217 | READ | 1.638 | 1.384 | 1.389 | 1.470 |
| **R25**: Premium audit: ads that were shown to users with an active Premium membership | READ | 29.474 | 37.897 | 29.888 | 32.420 |
| **W01**: Upload: a new public video on channel 217 | WRITE | 0.617 | 0.454 | 0.391 | 0.487 |
| **W02**: Player: record a view of video ZkNSlUB1EOs by user 1042 | WRITE | 0.570 | 0.526 | 0.481 | 0.526 |
| **W03**: View counter: add one view to video ZkNSlUB1EOs | WRITE | 0.228 | 0.225 | 0.187 | 0.213 |
| **W04**: Nightly job: recompute every channel's subscriber count | WRITE | 20.717 | 27.853 | 23.505 | 24.025 |
| **W05**: Publishing service: make scheduled videos public once their time has come | WRITE | 1.991 | 1.889 | 1.871 | 1.917 |
| **Total (sum of all 30)** | | **12311.913** | **12480.435** | **12834.232** | **12542.191** |

---

## 3. Plan Analysis & Execution Breakdown per Query

### R01: Channel Page — 20 Newest Public Videos (Avg: 2.672 ms)
- **Scan Type:** `Seq Scan on videos`
- **Reason:** Filters by `channel_id = 217` and `visibility = 'PUBLIC'` then sorts by `published_at DESC`. Without an index on `(channel_id, visibility, published_at)`, PostgreSQL scans all 30,000 video records and sorts them in memory.

### R02: Watch Page — One Video with Channel (Avg: 0.063 ms)
- **Scan Type:** `Index Scan using videos_pkey on videos | Index Scan using channels_pkey on channels`
- **Reason:** Fast point lookup. `video_id` is the primary key of `videos`, and the join matches `channels` on its primary key `channel_id`.

### R03: Subscriptions Feed (Avg: 3.286 ms)
- **Scan Type:** `Seq Scan on videos | Index Only Scan using subscriptions_pkey on subscriptions | Index Scan using channels_pkey on channels`
- **Reason:** Finding subscriptions for user 1042 uses the primary key index, but finding matching public videos requires a full sequential scan on `videos`.

### R04: Video Title Search (Avg: 11.604 ms)
- **Scan Type:** `Seq Scan on videos`
- **Reason:** The pattern match `title ILIKE '%tutorial%'` has a leading wildcard. Standard B-tree indexes cannot index substring searches, forcing a complete table scan and regex filter across all 30,000 video titles.

### R05: User Watch History (Avg: 4.265 ms)
- **Scan Type:** `Seq Scan on watch_events | Index Scan using videos_pkey on videos`
- **Reason:** Must scan all 200,000 rows in `watch_events` to locate views by `user_id = 1042` and sort by `started_at DESC`.

### R06: Scheduled Video Publishing Queue (Avg: 1.735 ms)
- **Scan Type:** `Seq Scan on videos`
- **Reason:** Scans all 30,000 rows in `videos` to filter for the 60 scheduled rows. A partial index on `visibility = 'SCHEDULED'` will make this instant.

### R07: Studio Daily Views & Watch Hours (Avg: 8.583 ms)
- **Scan Type:** `Seq Scan on watch_events | Seq Scan on videos`
- **Reason:** Full sequential scans on both `videos` and `watch_events` joined with a Hash Join and grouped by day.

### R08: Video Traffic Sources (Avg: 5.306 ms)
- **Scan Type:** `Seq Scan on watch_events`
- **Reason:** Filters 200,000 watch events by `video_id = 'ZkNSlUB1EOs'`. Without a secondary index on `watch_events(video_id)`, the full table must be read.

### R09: Studio Audience Retention (Avg: 8.087 ms)
- **Scan Type:** `Seq Scan on watch_events | Seq Scan on videos`
- **Reason:** Reads all 200k watch events and 30k videos to join and compute percentage watched per video of channel 217.

### R10: Shorts Shelf (Avg: 8.139 ms)
- **Scan Type:** `Seq Scan on watch_events | Seq Scan on videos`
- **Reason:** Scans both tables to filter on `videos.is_short = true` and `watch_events.started_at >= '2026-06-24'`.

### R11: Trending Tab Top 5 per Category (Avg: 14.536 ms)
- **Scan Type:** `Seq Scan on watch_events | Seq Scan on videos`
- **Reason:** Scans 200,000 rows, filters by date, aggregates view counts per video, and evaluates a window ranking function `RANK() OVER (PARTITION BY category ORDER BY count(*) DESC)`.

### R12: Logged-out Viewing per Device (Avg: 11.972 ms)
- **Scan Type:** `Seq Scan on watch_events`
- **Reason:** Scans all 200k rows in `watch_events` to group by `device` and compute the conditional count filter for `user_id IS NULL`.

### R13: Inactive Subscribers Report (Avg: 13.223 ms)
- **Scan Type:** `Index Scan using subscriptions_pkey on subscriptions | Seq Scan on watch_events | Seq Scan on videos`
- **Reason:** Performs sequential scans to find channel 217 viewers. Furthermore, due to the SQL NULL bug in `NOT IN (SELECT ...)`, it incorrectly evaluates to `UNKNOWN` and returns zero rows.

### R14: Studio Like/Dislike Ratio (Avg: 8.389 ms)
- **Scan Type:** `Seq Scan on video_reactions | Seq Scan on videos`
- **Reason:** Scans 67,417 reactions and 30,000 videos to aggregate reaction types for channel 217.

### R15: Watch Page Top Comments (Avg: 2.074 ms)
- **Scan Type:** `Seq Scan on comments`
- **Reason:** Scans all 60,000 comments to find top-level comments for video `ZkNSlUB1EOs` and sort by `is_pinned` and `like_count`.

### R16: Channel Ad Revenue in June 2026 (Avg: 17.505 ms)
- **Scan Type:** `Seq Scan on watch_events | Seq Scan on ad_impressions | Index Scan using videos_pkey on videos`
- **Reason:** Joins 57k ad impressions with 200k watch events and 30k videos using hash joins to aggregate revenue per channel.

### R17: Partner Program Eligibility (Avg: 13.484 ms)
- **Scan Type:** `Seq Scan on watch_events | Seq Scan on videos | Seq Scan on channels`
- **Reason:** 3-way sequential join across `channels`, `videos`, and `watch_events` filtering `NOT_ELIGIBLE` channels with 100+ subs and computing total watch hours.

### R18: Child Safety Comments Audit (Avg: 8.773 ms)
- **Scan Type:** `Seq Scan on comments | Seq Scan on videos`
- **Reason:** Scans `videos` for `is_made_for_kids = true` and performs correlated subquery lookups into `comments`.

### R19: Partner Upload and Total Views Report (Avg: 12295.087 ms)
- **Scan Type:** `Seq Scan on channels | Seq Scan on videos | Seq Scan on watch_events`
- **Reason:** **The primary bottleneck of the baseline workload (over 12.2 seconds).** For every single eligible channel (approx 850 rows), PostgreSQL executes two correlated scalar subqueries: one scanning `videos` for `MAX(uploaded_at)` and another scanning both `watch_events` (200,000 rows) and `videos` for `COUNT(*)`. This results in hundreds of repeated sequential scans.

### R20: Platform Daily Running Watch Hours (Avg: 8.534 ms)
- **Scan Type:** `Seq Scan on watch_events`
- **Reason:** Scans 200,000 watch events, filters date range with `started_at::date BETWEEN ...`, and computes a window running sum.

### R21: Playlist Video Sequence (Avg: 0.064 ms)
- **Scan Type:** `Index Scan using playlist_items_pkey on playlist_items | Index Scan using videos_pkey on videos`
- **Reason:** Fast index scan. `playlist_items` uses its composite primary key `(playlist_id, position)` to seek `playlist_id = 501` in order, followed by index lookups on `videos_pkey`.

### R22: Duplicate Uploads Copyright Audit (Avg: 20.445 ms)
- **Scan Type:** `Seq Scan on videos`
- **Reason:** Scans all 30,000 videos, performs a heavy hash aggregation on `(title, duration_sec)`, and filters groups with `HAVING count(DISTINCT channel_id) > 1`.

### R23: Moderation Queue Deep Pagination (Avg: 13.307 ms)
- **Scan Type:** `Seq Scan on comments`
- **Reason:** Scans 60,000 comments, sorts by `created_at DESC`, and skips 30,000 rows (`OFFSET 30000 LIMIT 25`).

### R24: Studio Monthly Subscriber Growth (Avg: 1.470 ms)
- **Scan Type:** `Index Scan using subscriptions_pkey on subscriptions`
- **Reason:** Leverages the primary key index on `subscriptions(user_id, channel_id)` (or index scan on channel) to gather rows for channel 217 and group by month.

### R25: Premium Ad Serving Compliance Audit (Avg: 32.420 ms)
- **Scan Type:** `Seq Scan on watch_events | Seq Scan on ad_impressions | Seq Scan on users`
- **Reason:** Multi-table join across `ad_impressions`, `watch_events`, and `users` to check `u.premium_until >= a.shown_at::date` without secondary indexes on timestamps or foreign keys.

### W01: Video Upload (Avg: 0.487 ms)
- **Scan Type:** `(no scan)`
- **Reason:** Single-row insertion into `videos`. Validates primary key and foreign key constraints.

### W02: Player Watch Event Logging (Avg: 0.526 ms)
- **Scan Type:** `(no scan)`
- **Reason:** Single-row insertion into `watch_events`. Fast transactional append.

### W03: View Counter Increment (Avg: 0.213 ms)
- **Scan Type:** `Index Scan using videos_pkey on videos`
- **Reason:** Point update on `videos` located via primary key index `videos_pkey`.

### W04: Nightly Subscriber Count Sync (Avg: 24.025 ms)
- **Scan Type:** `Seq Scan on channels | Seq Scan on subscriptions`
- **Reason:** Aggregates all 129,253 subscriptions by `channel_id` and updates all 3,000 rows in `channels` in a single bulk transaction.

### W05: Scheduled Video Publishing Batch (Avg: 1.917 ms)
- **Scan Type:** `Seq Scan on videos`
- **Reason:** Scans `videos` sequentially to identify and update scheduled videos whose publish timestamp has passed.

---

## 4. Key Takeaways & Optimization Targets

1. **R19 Dominates Total Latency:** `R19` accounts for **98.0% of total workload runtime** (12,295 ms out of 12,542 ms) due to correlated subqueries forcing quadratic nested table scans. Rewriting these subqueries into joins with aggregated CTEs or group-by subqueries will produce an enormous speed-up.
2. **Missing Foreign Key Indexes:** PostgreSQL does not automatically index foreign key columns. Tables like `watch_events(video_id)`, `watch_events(user_id)`, `comments(video_id)`, and `videos(channel_id)` suffer sequential scans on everyday join queries (`R01`, `R05`, `R07`, `R08`, `R15`, `R16`).
3. **Expression and Trigram Index Opportunities:** `R04` (`title ILIKE '%tutorial%'`) requires a GIN trigram index (`pg_trgm`), while `R07` and `R20` filter on expressions like `DATE(started_at)` which prevent standard B-tree range scans unless rewritten as sargable timestamp ranges.
4. **The R13 SQL Bug:** In addition to performance issues, `R13` returns 0 rows due to NULLs in `watch_events.user_id`. Replacing `NOT IN` with `NOT EXISTS` will correct the query output while speeding up execution.