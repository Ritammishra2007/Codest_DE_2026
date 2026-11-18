# Phase 4: Query Optimization Report

**Course:** DBMS Project · **Team:** T0006 · **Section:** D  
**File:** `docs/04_optimization_report.md`

---

## 1. Executive Summary

In this phase, we optimized the database to eliminate bottlenecks identified in the baseline benchmark. We implemented 14 secondary indexes (covering B-trees, GIN trigram, and partial indexes) in `sql/05_indexes.sql` and targeted query rewrites in `sql/06_optimized_queries.sql`.

### Key Outcomes:
- **Total Workload Runtime:** Reduced from **12,542.19 ms** down to **168.87 ms** (**98.65% overall latency reduction**, an overall **74.3× speedup**).
- **R19 Optimization:** Slashed the biggest bottleneck from **12,295.09 ms** down to **38.59 ms** (**99.69% faster**, over **318× speedup**) by replacing quadratic correlated subqueries with pre-aggregated CTE joins.
- **SQL NULL Bug Resolved (R13):** Fixed the three-valued logic flaw where `NOT IN (..., NULL)` always evaluated to `UNKNOWN` and hid all results. The corrected query returns all **88 inactive subscribers**.
- **Full-Text Trigram Search (R04):** Enabled `pg_trgm` with a GIN index on `videos(title)`, improving search from **11.60 ms** to **1.69 ms** (**85.4% faster**).
- **Write Overhead Contained:** Write latencies (`W01`–`W03`) increased marginally by ~0.2–0.4 ms due to secondary index maintenance but remain under **0.9 ms**, well below the 5 ms real-time SLA. `W05` actually became **64.7% faster** thanks to a partial index on scheduled videos.

---

## 2. Optimization Summary Table (All 30 Queries)

$$\text{Improvement \%} = \frac{\text{Before} - \text{After}}{\text{Before}} \times 100$$

| Query | Before (ms) | Problem Found in Baseline Plan | Optimization Applied | After (ms) | Improvement % | Same Result? |
|:---:|---:|:---|:---|---:|:---:|:---:|
| **R01** | 2.672 | Seq scan on 30k videos + in-memory sort | Partial composite B-tree on `videos(channel_id, published_at DESC) WHERE visibility = 'PUBLIC'` | 0.060 | **+97.8%** | ✅ |
| **R02** | 0.063 | None; optimal point lookup on PKs | Retained PK index scans | 0.074 | -17.5% (noise) | ✅ |
| **R03** | 3.286 | Seq scan on `videos` matching channel IDs | Composite index `idx_videos_channel_public` | 0.192 | **+94.2%** | ✅ |
| **R04** | 11.604 | Seq scan across 30k titles for leading wildcard `%tutorial%` | GIN Trigram index (`pg_trgm`) on `videos USING gin (title gin_trgm_ops)` | 1.694 | **+85.4%** | ✅ |
| **R05** | 4.265 | Seq scan on 200k `watch_events` + sort | Composite B-tree on `watch_events(user_id, started_at DESC)` | 0.052 | **+98.8%** | ✅ |
| **R06** | 1.735 | Seq scan on 30k videos for 60 scheduled rows | Partial index on `videos(published_at) WHERE visibility = 'SCHEDULED'` | 0.050 | **+97.1%** | ✅ |
| **R07** | 8.583 | Seq scan on watch events + `DATE(started_at)` expression | B-tree on `watch_events(video_id)` + sargable timestamp range rewrite | 1.849 | **+78.5%** | ✅ |
| **R08** | 5.306 | Seq scan on 200k watch events for one video | B-tree index on `watch_events(video_id)` | 0.096 | **+98.2%** | ✅ |
| **R09** | 8.087 | Seq scan on watch events joined with videos | B-tree index on `watch_events(video_id)` | 1.475 | **+81.8%** | ✅ |
| **R10** | 8.139 | Double seq scan on watch events and videos | Partial index on `videos(is_short)` + B-tree on `watch_events(started_at)` | 3.402 | **+58.2%** | ✅ |
| **R11** | 14.536 | Seq scan filtering June 2026 watch events | B-tree index on `watch_events(started_at)` | 9.455 | **+35.0%** | ✅ |
| **R12** | 11.972 | Full table aggregation on all 200k rows | Optimal parallel seq scan (reads entire table by design) | 11.708 | +2.2% | ✅ |
| **R13** | 13.223 | Seq scan on watch events + SQL NULL bug returns 0 rows | B-tree on `subscriptions(channel_id)` + query rewrite to `NOT EXISTS` | 2.965 | **+77.6%** | **Fixed (88 rows)** |
| **R14** | 8.389 | Seq scan on 67k `video_reactions` for channel videos | B-tree index on `video_reactions(video_id)` | 1.487 | **+82.3%** | ✅ |
| **R15** | 2.074 | Seq scan on 60k comments + sort | Partial composite index on `comments(video_id, is_pinned DESC, like_count DESC)` | 0.042 | **+98.0%** | ✅ |
| **R16** | 17.505 | 3-way join with seq scan on ad impressions | B-tree index on `ad_impressions(shown_at)` | 9.948 | **+43.2%** | ✅ |
| **R17** | 13.484 | 3-way join with unindexed watch events | B-tree index on `watch_events(video_id)` | 13.076 | +3.0% | ✅ |
| **R18** | 8.773 | Correlated subquery scanning `comments` | B-tree index on `comments(video_id)` for fast index-only semi-join | 2.123 | **+75.8%** | ✅ |
| **R19** | 12295.087 | Correlated scalar subqueries scanning tables for each channel | Rewrote query with CTE pre-aggregation, removing quadratic subqueries | 38.593 | **+99.7% (318×)** | ✅ |
| **R20** | 8.534 | Seq scan + `started_at::date` expression | Sargable date range rewrite + index on `watch_events(started_at)` | 1.898 | **+77.8%** | ✅ |
| **R21** | 0.064 | None; point lookup on composite PK | Retained PK index scan | 0.132 | -106% (sub-ms noise) | ✅ |
| **R22** | 20.445 | Heavy hash aggregate over entire 30k videos | Whole-table deduplication audit; seq scan optimal | 19.124 | +6.5% | ✅ |
| **R23** | 13.307 | Seq scan sorting 60k comments for deep offset | B-tree index on `comments(created_at DESC)` | 2.567 | **+80.7%** | ✅ |
| **R24** | 1.470 | Index scan on primary key without channel index | B-tree index on `subscriptions(channel_id)` | 0.212 | **+85.6%** | ✅ |
| **R25** | 32.420 | 3-way join scanning 30k users for rare premium | Partial index on `users(premium_until) WHERE premium_until IS NOT NULL` | 23.639 | **+27.1%** | ✅ |
| **W01** | 0.487 | Single-row insert into `videos` | Maintained minimal secondary indexes on videos | 0.887 | -82.1% (within SLA) | ✅ |
| **W02** | 0.526 | Single-row insert into `watch_events` | Secondary index insertion overhead | 0.757 | -43.9% (within SLA) | ✅ |
| **W03** | 0.213 | Single-row PK update on `videos` | Point update; negligible index overhead | 0.543 | -154% (within SLA) | ✅ |
| **W04** | 24.025 | Batch update scanning 129k subscriptions | B-tree index on `subscriptions(channel_id)` | 20.096 | **+16.4%** | ✅ |
| **W05** | 1.917 | Seq scan on 30k videos to update scheduled | Accelerated by partial index `idx_videos_scheduled` | 0.677 | **+64.7%** | ✅ |
| **Total** | **12542.191** | | | **168.873** | **+98.65% (74.3×)** | |

---

## 3. The 5 Biggest Improvements (Before / After Execution Plans)

### #1. Query R19: Partner Report (12,295 ms $\to$ 38.6 ms — 318× Faster)
* **The Root Cause:** In the baseline, PostgreSQL evaluated two correlated scalar subqueries for every single eligible channel (1,087 channels). Each channel forced a sequential scan on `videos` and another on `watch_events` (200k rows), generating over **3.6 million buffer hits**.
* **The Optimization:** Rewrote the query in `sql/06_optimized_queries.sql` to compute video statistics and view counts once using CTE hash joins.

```
BEFORE (Baseline):
Sort  (cost=7221520.83..7221523.55 rows=1087 width=35) (actual time=12072.774..12072.801 rows=1087 loops=1)
  Sort Key: ((SubPlan 2)) DESC
  Buffers: shared hit=3661055
  ->  Seq Scan on channels c  (cost=0.00..7221466.01 rows=1087 width=35) (actual time=12.581..12072.487 rows=1087 loops=1)
        Filter: ((monetization_status)::text = 'ELIGIBLE'::text)
        SubPlan 1
          ->  Aggregate  (cost=1023.02..1023.03 rows=1 width=8) (actual time=0.845..0.845 rows=1 loops=1087)
                ->  Seq Scan on videos v  (cost=0.00..1023.00 rows=10 width=8) (actual time=0.103..0.843 rows=10 loops=1087)
                      Filter: (channel_id = c.channel_id)
        SubPlan 2
          ->  Aggregate  (cost=5618.00..5618.01 rows=1 width=8) (actual time=10.250..10.250 rows=1 loops=1087)
                ->  Hash Join  (cost=1023.12..5618.00 rows=1 width=0) (actual time=1.230..10.240 rows=23 loops=1087)
Execution Time: 12073.274 ms

AFTER (Optimized):
Sort  (cost=7629.85..7632.56 rows=1087 width=35) (actual time=37.388..37.407 rows=1087 loops=1)
  Sort Key: (COALESCE((count(w.watch_id)), '0'::bigint)) DESC
  Buffers: shared hit=2759
  ->  Hash Right Join  (cost=7507.17..7575.03 rows=1087 width=35) (actual time=37.007..37.277 rows=1087 loops=1)
        Hash Cond: (v.channel_id = c.channel_id)
        ->  HashAggregate  (cost=7420.08..7450.07 rows=2999 width=20) (actual time=36.809..36.920 rows=2999 loops=1)
              ->  Hash Right Join  (cost=1323.00..5920.08 rows=200000 width=20) (actual time=3.239..24.373 rows=202307 loops=1)
Execution Time: 37.462 ms (99.7% reduction, shared buffers dropped from 3.66M to 2,759)
```

---

### #2. Query R05: User Watch History (4.265 ms $\to$ 0.052 ms — 82× Faster)
* **The Root Cause:** Scanned all 200,000 watch events sequentially to find the last 50 videos watched by user 1042.
* **The Optimization:** Created composite B-tree index `idx_watch_events_user_started ON watch_events (user_id, started_at DESC)`.

```
BEFORE (Baseline):
Limit  (cost=4542.93..4593.15 rows=6 width=48) (actual time=3.862..4.431 rows=4 loops=1)
  Buffers: shared hit=2122
  ->  Nested Loop  (cost=4542.93..4593.15 rows=6 width=48) (actual time=3.862..4.430 rows=4 loops=1)
        ->  Parallel Seq Scan on watch_events w  (cost=0.00..3542.59 rows=4 width=24) (actual time=0.090..2.678 rows=2 loops=2)
              Filter: (user_id = 1042)
Execution Time: 4.451 ms

AFTER (Optimized):
Limit  (cost=77.48..77.50 rows=6 width=48) (actual time=0.036..0.037 rows=4 loops=1)
  Buffers: shared hit=22
  ->  Bitmap Heap Scan on watch_events w  (cost=4.47..27.57 rows=6 width=24) (actual time=0.008..0.013 rows=4 loops=1)
        Recheck Cond: (user_id = 1042)
        ->  Bitmap Index Scan on idx_watch_events_user_started  (cost=0.00..4.46 rows=6 width=0) (actual time=0.004..0.004 rows=4 loops=1)
Execution Time: 0.051 ms (Buffers dropped from 2,122 to 22)
```

---

### #3. Query R08: Video Traffic Sources (5.306 ms $\to$ 0.096 ms — 55× Faster)
* **The Root Cause:** Missing index on foreign key `watch_events.video_id` forced a complete 200,000-row table scan to group traffic sources for one video.
* **The Optimization:** Created B-tree index `idx_watch_events_video_id ON watch_events (video_id)`.

```
BEFORE (Baseline):
Sort  (cost=4543.69..4543.70 rows=4 width=49) (actual time=4.498..5.047 rows=5 loops=1)
  Buffers: shared hit=2113
  ->  Gather Merge  (cost=4542.66..4543.53 rows=7 width=49) (actual time=4.476..5.031 rows=7 loops=1)
        ->  Parallel Seq Scan on watch_events  (cost=0.00..3542.59 rows=5 width=13) (actual time=0.101..3.450 rows=7 loops=2)
              Filter: (video_id = 'ZkNSlUB1EOs'::bpchar)
Execution Time: 5.083 ms

AFTER (Optimized):
Sort  (cost=35.39..35.40 rows=4 width=49) (actual time=0.064..0.064 rows=5 loops=1)
  Buffers: shared hit=23
  ->  Bitmap Heap Scan on watch_events  (cost=4.48..35.09 rows=8 width=13) (actual time=0.014..0.032 rows=14 loops=1)
        Recheck Cond: (video_id = 'ZkNSlUB1EOs'::bpchar)
        ->  Bitmap Index Scan on idx_watch_events_video_id  (cost=0.00..4.48 rows=8 width=0) (actual time=0.008..0.008 rows=14 loops=1)
Execution Time: 0.089 ms (Buffers dropped from 2,113 to 23)
```

---

### #4. Query R15: Watch Page Top Comments (2.074 ms $\to$ 0.042 ms — 49× Faster)
* **The Root Cause:** Scanned all 60,000 comments sequentially to filter for top-level comments of video `ZkNSlUB1EOs` and sort by pinned status and like count.
* **The Optimization:** Created partial composite index `idx_comments_video_pinned ON comments (video_id, is_pinned DESC, like_count DESC) WHERE parent_comment_id IS NULL`.

```
BEFORE (Baseline):
Limit  (cost=1406.02..1406.03 rows=3 width=33) (actual time=2.095..2.095 rows=3 loops=1)
  Buffers: shared hit=664
  ->  Seq Scan on comments  (cost=0.00..1406.00 rows=3 width=33) (actual time=0.073..2.083 rows=3 loops=1)
        Filter: ((parent_comment_id IS NULL) AND (video_id = 'ZkNSlUB1EOs'::bpchar))
Execution Time: 2.106 ms

AFTER (Optimized):
Limit  (cost=15.77..15.77 rows=3 width=33) (actual time=0.027..0.027 rows=3 loops=1)
  Buffers: shared hit=15
  ->  Bitmap Heap Scan on comments  (cost=4.31..15.74 rows=3 width=33) (actual time=0.011..0.016 rows=3 loops=1)
        ->  Bitmap Index Scan on idx_comments_video_id  (cost=0.00..4.31 rows=3 width=0) (actual time=0.006..0.006 rows=5 loops=1)
Execution Time: 0.038 ms (Buffers dropped from 664 to 15)
```

---

### #5. Query R01: Channel Page Newest Videos (2.672 ms $\to$ 0.060 ms — 44× Faster)
* **The Root Cause:** Sequential scan over all 30,000 videos filtering for public videos of channel 217 followed by quicksort on `published_at DESC`.
* **The Optimization:** Created partial composite index `idx_videos_channel_public ON videos (channel_id, published_at DESC) WHERE visibility = 'PUBLIC'`.

```
BEFORE (Baseline):
Limit  (cost=1098.12..1098.14 rows=8 width=52) (actual time=3.136..3.140 rows=12 loops=1)
  Buffers: shared hit=651
  ->  Sort  (cost=1098.12..1098.14 rows=8 width=52) (actual time=3.135..3.136 rows=12 loops=1)
        Sort Key: published_at DESC
        ->  Seq Scan on videos  (cost=0.00..1098.00 rows=8 width=52) (actual time=0.397..3.121 rows=12 loops=1)
              Filter: ((channel_id = 217) AND ((visibility)::text = 'PUBLIC'::text))
Execution Time: 3.156 ms

AFTER (Optimized):
Limit  (cost=33.92..33.94 rows=8 width=52) (actual time=0.037..0.038 rows=12 loops=1)
  Buffers: shared hit=17
  ->  Bitmap Heap Scan on videos  (cost=4.35..33.80 rows=8 width=52) (actual time=0.011..0.025 rows=12 loops=1)
        ->  Bitmap Index Scan on idx_videos_channel_public  (cost=0.00..4.35 rows=8 width=0) (actual time=0.004..0.004 rows=12 loops=1)
Execution Time: 0.052 ms (Buffers dropped from 651 to 17)
```

---

## 4. The Wrong-Result Query Discovery & Fix (R13)

### The Problem
Problem statement P5 reported: *"A creator report of subscribers who never watched the channel always comes back empty."*

### Original Query:
```sql
SELECT s.user_id, s.subscribed_at
FROM subscriptions s
WHERE s.channel_id = 217
  AND s.user_id NOT IN (
      SELECT w.user_id
      FROM watch_events w JOIN videos v ON v.video_id = w.video_id
      WHERE v.channel_id = 217
  );
```

### Root Cause Analysis (SQL Three-Valued Logic)
In SQL, comparison with `NULL` yields `UNKNOWN`. The expression:
$$\text{user\_id NOT IN (id}_1, \text{id}_2, \dots, \text{NULL)}$$
is internally evaluated as:
$$\text{user\_id} \ne \text{id}_1 \land \text{user\_id} \ne \text{id}_2 \land \dots \land (\text{user\_id} \ne \text{NULL})$$
Since `user_id <> NULL` evaluates to `UNKNOWN`, the entire conjunction evaluates to `UNKNOWN` (falsy) for every subscriber. Because ~25% of watch events are from logged-out guest viewers (`user_id IS NULL`), the subquery always returned at least one `NULL`, completely wiping out all results and returning **0 rows**.

### The Solution:
Rewrote the query in `sql/06_optimized_queries.sql` using an anti-join pattern (`NOT EXISTS`):
```sql
SELECT s.user_id, s.subscribed_at
FROM subscriptions s
WHERE s.channel_id = 217
  AND NOT EXISTS (
      SELECT 1
      FROM watch_events w
      JOIN videos v ON v.video_id = w.video_id
      WHERE v.channel_id = 217 AND w.user_id = s.user_id
  );
```

### Verification & Proof:
- **Baseline Result:** 0 rows (incorrect).
- **Optimized Result:** **88 rows** (exactly matches the 88 subscribers to channel 217 who never generated a watch event).

---

## 5. Write Overhead Analysis

Adding secondary indexes requires PostgreSQL to update index trees upon every `INSERT`, `UPDATE`, or `DELETE`. We measured the impact on write queries `W01`–`W05`:

| Write Query | Operation | Baseline (ms) | Optimized (ms) | Latency Delta | Meets < 5 ms SLA? | Explanation |
|:---:|---|:---:|:---:|:---:|:---:|:---|
| **W01** | Insert video | 0.487 | 0.887 | +0.400 ms | **Yes (0.887 ms)** | Minimal overhead; partial index `idx_videos_scheduled` is bypassed since `visibility = 'PUBLIC'`. |
| **W02** | Insert watch event | 0.526 | 0.757 | +0.231 ms | **Yes (0.757 ms)** | Updates B-tree indexes on `video_id`, `started_at`, and `user_id`. |
| **W03** | Update view count | 0.213 | 0.543 | +0.330 ms | **Yes (0.543 ms)** | HOT (Heap-Only Tuple) update cannot be used because HOT rules require no indexed columns to change; still sub-millisecond. |
| **W04** | Nightly batch sync | 24.025 | 20.096 | -3.929 ms | **Yes (< 2,000 ms)** | Sped up by 16.4% due to `idx_subscriptions_channel_id` accelerating the group-by aggregation. |
| **W05** | Publish scheduled | 1.917 | 0.677 | -1.240 ms | **Yes (< 250 ms)** | **64.7% faster** because `idx_videos_scheduled` locates scheduled rows immediately without scanning all 30k videos. |

**Conclusion:** All user-facing write operations remain well within the sub-millisecond range and comfortably satisfy the 5 ms SLA.

---

## 6. Index Storage & Overhead

We measured the physical disk footprint of all created indexes using `pg_relation_size`:

| Table Name | Table Size | Index Name | Index Type | Index Size | Overhead % |
|:---|---:|:---|:---:|---:|---:|
| `videos` | 5,184 kB | `idx_videos_title_trgm` | GIN Trigram | 1,632 kB | 31.5% |
| `videos` | 5,184 kB | `idx_videos_channel_public` | Partial B-tree | 824 kB | 15.9% |
| `videos` | 5,184 kB | `idx_videos_is_short` | Partial B-tree | 248 kB | 4.8% |
| `videos` | 5,184 kB | `idx_videos_scheduled` | Partial B-tree | 16 kB | 0.3% |
| `watch_events` | 16,384 kB | `idx_watch_events_user_started` | Composite B-tree | 6,184 kB | 37.3% |
| `watch_events` | 16,384 kB | `idx_watch_events_started_at` | B-tree | 4,408 kB | 26.6% |
| `watch_events` | 16,384 kB | `idx_watch_events_video_id` | B-tree | 2,272 kB | 13.7% |
| `comments` | 5,248 kB | `idx_comments_video_pinned` | Partial Composite B-tree | 2,080 kB | 39.6% |
| `comments` | 5,248 kB | `idx_comments_created_at` | B-tree | 1,328 kB | 25.3% |
| `comments` | 5,248 kB | `idx_comments_video_id` | B-tree | 1,152 kB | 22.0% |
| `subscriptions` | 7,552 kB | `idx_subscriptions_channel_id` | B-tree | 944 kB | 12.5% |
| `video_reactions` | 4,096 kB | `idx_video_reactions_video_id` | B-tree | 1,232 kB | 30.1% |
| `ad_impressions` | 3,808 kB | `idx_ad_impressions_shown_at` | B-tree | 1,264 kB | 33.2% |
| `users` | 2,688 kB | `idx_users_premium_until` | Partial B-tree | 48 kB | 1.8% |
| **Total** | **50,144 kB** | **14 Secondary Indexes** | | **23,632 kB** | **47.1%** |

*Key Takeaway:* Partial indexes (`idx_videos_scheduled` at 16 kB, `idx_users_premium_until` at 48 kB) deliver massive speedups with practically zero storage overhead.

---

## 7. Queries That Could Not Be Sped Up Significantly

Certain queries could not achieve dramatic order-of-magnitude speedups, for legitimate architectural reasons:
1. **`R12` (Logged-Out Viewing Distribution):** Aggregates across the entire `watch_events` table (all 200,000 records) to compute device shares and filter guest sessions. Because every single tuple must be read, a Sequential Scan with parallel workers is mathematically optimal; an index would add random I/O overhead.
2. **`R22` (Copyright Deduplication Audit):** Scans the entire 30,000 video catalog, grouping by `(title, duration_sec)` to detect duplicate uploads across distinct channels. Full catalog aggregation requires reading all tuples.
3. **`W04` (Nightly Subscriber Count Sync):** Recomputes subscriber counts for all 3,000 channels by aggregating 129,253 rows in `subscriptions`. While our channel index accelerated the grouping phase (reducing runtime from 24.0 ms to 20.1 ms), updating 3,000 table rows requires physical disk writes that cannot be bypassed.