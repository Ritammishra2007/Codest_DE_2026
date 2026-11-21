-- =====================================================================
-- YouTube Video Sharing Database: Table Partitioning Architecture
-- File: sql/08_partitioning.sql
--
-- Demonstrates horizontal range partitioning on the highest-volume table
-- (watch_events) to enable partition pruning, fast data archiving, and
-- linear scalability up to 100x volume.
-- =====================================================================

SET search_path TO youtube, public;

-- =====================================================================
-- 1. WHY PARTITION WATCH_EVENTS?
-- =====================================================================
-- 1. Volume: watch_events grows orders of magnitude faster than any other entity
--    (200k in seed, 4M in large dataset, billions at production scale).
-- 2. Temporal Locality: Over 90% of analytics and viewer queries (R07, R10, R11,
--    R16, R20) query recent time windows (e.g., June 2026 or last 7 days).
-- 3. Partition Pruning: Queries with date filters scan ONLY the relevant monthly
--    partitions, completely skipping historical months.
-- 4. Fast Maintenance & Archival: Old data can be dropped or archived in milliseconds
--    via ALTER TABLE DETACH PARTITION without expensive DELETE operations or VACUUM locks.

-- =====================================================================
-- 2. POSTGRESQL PRIMARY KEY RULE FOR PARTITIONED TABLES
-- =====================================================================
-- Rule: In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY
-- constraint on a partitioned table MUST include the partition key column(s).
-- If we only used PRIMARY KEY (watch_id), PostgreSQL would have to check uniqueness
-- across all partitions on every insert, defeating the purpose of isolation.
-- Therefore, the composite key is: PRIMARY KEY (watch_id, started_at).

-- Drop partitioned demo table if exists
DROP TABLE IF EXISTS watch_events_partitioned CASCADE;

-- Create partitioned parent table
CREATE TABLE watch_events_partitioned (
    watch_id       BIGINT      NOT NULL,
    user_id        INT         NULL,
    video_id       CHAR(11)    NOT NULL,
    started_at     TIMESTAMPTZ NOT NULL,
    watch_seconds  INT         NOT NULL,
    device         VARCHAR(20) NOT NULL,
    traffic_source VARCHAR(20) NOT NULL,

    -- Composite PK including partition key
    CONSTRAINT pk_watch_events_partitioned PRIMARY KEY (watch_id, started_at),

    -- Foreign keys
    CONSTRAINT fk_watch_part_user  FOREIGN KEY (user_id) 
        REFERENCES users (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_watch_part_video FOREIGN KEY (video_id) 
        REFERENCES videos (video_id) ON DELETE CASCADE,

    -- Check constraints
    CONSTRAINT chk_watch_part_seconds CHECK (watch_seconds >= 0),
    CONSTRAINT chk_watch_part_device  CHECK (device IN ('ANDROID', 'IOS', 'TV', 'WEB')),
    CONSTRAINT chk_watch_part_traffic CHECK (traffic_source IN ('EXTERNAL', 'HOME', 'SEARCH', 'SHORTS_FEED', 'SUBSCRIPTION', 'SUGGESTED'))
) PARTITION BY RANGE (started_at);

-- =====================================================================
-- 3. CREATE MONTHLY PARTITIONS
-- =====================================================================

-- Partitions for 2025
CREATE TABLE watch_events_2025_01 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-02-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_02 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-02-01 00:00:00+05:30') TO ('2025-03-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_03 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-03-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_04 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-05-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_05 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-05-01 00:00:00+05:30') TO ('2025-06-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_06 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-06-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_07 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-08-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_08 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-08-01 00:00:00+05:30') TO ('2025-09-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_09 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-09-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_10 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2025-11-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_11 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-11-01 00:00:00+05:30') TO ('2025-12-01 00:00:00+05:30');

CREATE TABLE watch_events_2025_12 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2025-12-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- Partitions for 2026
CREATE TABLE watch_events_2026_01 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-02-01 00:00:00+05:30');

CREATE TABLE watch_events_2026_02 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00+05:30') TO ('2026-03-01 00:00:00+05:30');

CREATE TABLE watch_events_2026_03 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2026-03-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE watch_events_2026_04 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-05-01 00:00:00+05:30');

CREATE TABLE watch_events_2026_05 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2026-05-01 00:00:00+05:30') TO ('2026-06-01 00:00:00+05:30');

CREATE TABLE watch_events_2026_06 PARTITION OF watch_events_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

-- Default partition for future timestamps or overflow
CREATE TABLE watch_events_default PARTITION OF watch_events_partitioned DEFAULT;

-- =====================================================================
-- 4. PARTITION-AWARE SECONDARY INDEXES
-- Indexes defined on the partitioned parent table are automatically
-- created on every partition.
-- =====================================================================
CREATE INDEX idx_part_watch_user_started ON watch_events_partitioned (user_id, started_at DESC);
CREATE INDEX idx_part_watch_video_id ON watch_events_partitioned (video_id);

-- =====================================================================
-- 5. POPULATE FROM CURRENT WATCH_EVENTS TABLE (FOR PROOF)
-- =====================================================================
INSERT INTO watch_events_partitioned 
SELECT * FROM watch_events;

ANALYZE watch_events_partitioned;

-- =====================================================================
-- 6. PARTITION PRUNING DEMONSTRATION WITH EXPLAIN
-- Query targeting only June 2026: PostgreSQL will prune away 17 partitions
-- and scan ONLY watch_events_2026_06!
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS june_views, round(sum(watch_seconds)/3600.0, 1) AS june_hours
FROM watch_events_partitioned
WHERE started_at >= '2026-06-01 00:00:00+05:30' 
  AND started_at < '2026-07-01 00:00:00+05:30';
