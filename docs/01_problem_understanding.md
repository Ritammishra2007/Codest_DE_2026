# Phase 1: Problem Understanding

**Course:** DBMS Project · **Team:** T0006 · **Section:** D  
**File:** `docs/01_problem_understanding.md`

---

## 1. Project Overview

YouTube lets creators upload videos (regular videos and Shorts) and run channels. Viewers can watch videos, like or dislike, write comments, subscribe to channels, and create playlists. Monetized channels earn money from ads, but YouTube Premium members should never see ads.

The current database was built without proper design:
- It has no indexes or constraints yet.
- Everyday user pages are slow.
- Creator analytics dashboards lag.
- Some reports time out or give wrong answers.

Our goal is to understand all 9 reported problems, fix the schema, optimize the queries, and make the database ready for 20× more data.

---

## 2. Problems Analysis (P1 to P9)

### P1: Slow Channel Pages, Watch Pages, and Playlists
- **What is wrong:** When a viewer opens a channel profile, clicks a video to watch, loads the comments, or opens a playlist, the page takes too long to load.
- **Who is affected:** Viewers (bad user experience) and Creators (channels feel slow).
- **Classification:** **Customer-Facing / Real-Time** (Target: **under 5 ms**).
- **Queries:** `R01`, `R02`, `R15`, `R21`.

### P2: Slow Subscriptions Feed and Watch History
- **What is wrong:** Signed-in users have to wait several seconds to see new videos from channels they subscribe to, or to see their recent watch history.
- **Who is affected:** Signed-in Viewers.
- **Classification:** **Customer-Facing / Real-Time** (Target: **under 5 ms**).
- **Queries:** `R03`, `R05`.

### P3: Video Search by Title is Too Slow
- **What is wrong:** Searching for videos by keyword in the title (like "tutorial") scans through every single row in the database, making search sluggish.
- **Who is affected:** Viewers and the Search Team.
- **Classification:** **Interactive / Search** (Target: **under 250 ms**).
- **Queries:** `R04`.

### P4: YouTube Studio Creator Dashboards Lag
- **What is wrong:** Creators check YouTube Studio for daily views, watch hours, traffic sources, audience retention, and likes, but the charts take too long to compute.
- **Who is affected:** Creators and the YouTube Studio Team.
- **Classification:** **Interactive Studio** (Target: **under 250 ms**).
- **Queries:** `R07`, `R08`, `R09`, `R14`, `R24`.

### P5: Inactive Subscribers Report Always Returns Empty
- **What is wrong:** Creators want a list of subscribers who never watched any video on their channel, but the report always returns 0 rows.
- **Why this happens:** The query uses `NOT IN` with a subquery that contains `NULL` values (from logged-out viewers). In SQL, `NOT IN (..., NULL)` always evaluates to `UNKNOWN` (false), hiding all results.
- **Who is affected:** Creators.
- **Classification:** **Interactive Studio** (Target: **under 250 ms**).
- **Queries:** `R13`.

### P6: Shorts Shelf and Trending Tab Recompute Slowly
- **What is wrong:** Recomputing the top Shorts from the last 7 days and ranking top 5 trending videos per category takes too much time.
- **Who is affected:** Viewers and the Recommendations Team.
- **Classification:** **Reporting / Analytics** (Target: **under 5,000 ms**).
- **Queries:** `R10`, `R11`.

### P7: Scheduled Videos Missed and Slow Video Writes
- **What is wrong:** The background service that turns scheduled videos public runs late; simultaneously, new video uploads and view counter updates slow down when traffic spikes.
- **Who is affected:** Creators and the Publishing Service.
- **Classification:**
  - Real-time writes (`W01`, `W02`, `W03`): **under 5 ms**.
  - Background scheduler (`R06`, `W05`): **under 250 ms**.
- **Queries:** `R06`, `W01`, `W02`, `W03`, `W05`.

### P8: Finance and Partner Program Reports Time Out
- **What is wrong:** Calculating monthly ad revenue per channel, checking channels that qualify for monetization, and checking if ads were accidentally shown to Premium members take too long or crash.
- **Who is affected:** Finance Team, Partner Program Team, and Premium Subscribers.
- **Classification:**
  - Analytics & Audits (`R16`, `R17`, `R19`, `R25`): **under 5,000 ms**.
  - Nightly subscriber sync (`W04`): **under 2,000 ms**.
- **Queries:** `R16`, `R17`, `R19`, `R25`, `W04`.

### P9: Trust, Safety, Copyright, and 20× Scale
- **What is wrong:** Reports needed for child safety (detecting comments on kids videos), copyright (duplicate video uploads), and comment moderation queues are very slow, and the database must handle 20× more data soon.
- **Who is affected:** Trust & Safety Team, Legal Team, Moderation Team.
- **Classification:** **Reporting / Analytics** (Target: **under 5,000 ms**).
- **Queries:** `R12`, `R18`, `R20`, `R22`, `R23`.

---

## 3. Workload Classification Summary

| Category | SLA Target | Queries | Purpose |
|---|:---:|---|---|
| **Real-Time (User-facing)** | **< 5 ms** | `R01`, `R02`, `R03`, `R05`, `R15`, `R21`, `W01`, `W02`, `W03` | Fast page loads and instant user actions. |
| **Interactive Studio & Search** | **< 250 ms** | `R04`, `R06`, `R07`, `R08`, `R09`, `R13`, `R14`, `R24`, `W05` | Creator dashboards, search bar, and publishing queue. |
| **Reports & Safety Analytics** | **< 5,000 ms** | `R10`, `R11`, `R12`, `R16`, `R17`, `R18`, `R19`, `R20`, `R22`, `R23`, `R25` | Business reports, trending lists, and moderation audits. |
| **Batch Reconciliation** | **< 2,000 ms** | `W04` | Nightly background sync of subscriber counts. |

---

## 4. Key Assumptions

1. **Guest Viewers:** People can watch videos without logging in. Therefore, `watch_events.user_id` can be empty (`NULL`).
2. **Logical Time Constraints:**
   - A video cannot be watched before it is uploaded.
   - A watch event cannot be longer than the video's total duration.
3. **Shorts Definition:** Any video with a duration of 60 seconds or less is a Short (`is_short = true`).
4. **Denormalized Counters:** `view_count` on videos and `subscriber_count` on channels are saved directly in the table to avoid counting millions of rows on every page click.
5. **Private Videos:** Private videos do not have a published date (`published_at IS NULL`).

