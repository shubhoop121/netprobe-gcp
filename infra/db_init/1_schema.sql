-- =======================================================================
-- 1. LOGGING TABLES (Partitioned + JSONB)
-- =======================================================================

-- CONNECTIONS (Zeek)
CREATE TABLE IF NOT EXISTS connections (
    ts TIMESTAMPTZ NOT NULL,
    uid TEXT NOT NULL,
    source_ip INET NOT NULL,
    source_port INT,
    destination_ip INET NOT NULL,
    destination_port INT,
    proto TEXT,
    service TEXT,
    duration REAL,
    orig_bytes BIGINT,
    resp_bytes BIGINT,
    conn_state TEXT,
    details JSONB,
    PRIMARY KEY (ts, uid)
) PARTITION BY RANGE (ts);

-- ALERTS (Suricata)
CREATE TABLE IF NOT EXISTS alerts (
    timestamp TIMESTAMPTZ NOT NULL,
    alert_id TEXT NOT NULL,
    source_ip INET NOT NULL,
    destination_ip INET NOT NULL,
    signature_id INT,
    signature TEXT,
    severity INT,
    details JSONB,
    PRIMARY KEY (timestamp, alert_id)
) PARTITION BY RANGE (timestamp);

-- =======================================================================
-- 2. PARTITION MAINTENANCE (Manual Seed)
-- =======================================================================
-- We create 'default', 'yesterday', and 'today' to ensure immediate functionality.
-- The automated maintenance script will handle future days.

CREATE TABLE IF NOT EXISTS connections_default PARTITION OF connections DEFAULT;
CREATE TABLE IF NOT EXISTS connections_yest PARTITION OF connections
    FOR VALUES FROM (CURRENT_DATE - INTERVAL '1 day') TO (CURRENT_DATE);
CREATE TABLE IF NOT EXISTS connections_today PARTITION OF connections
    FOR VALUES FROM (CURRENT_DATE) TO (CURRENT_DATE + INTERVAL '1 day');

CREATE TABLE IF NOT EXISTS alerts_default PARTITION OF alerts DEFAULT;
CREATE TABLE IF NOT EXISTS alerts_yest PARTITION OF alerts
    FOR VALUES FROM (CURRENT_DATE - INTERVAL '1 day') TO (CURRENT_DATE);
CREATE TABLE IF NOT EXISTS alerts_today PARTITION OF alerts
    FOR VALUES FROM (CURRENT_DATE) TO (CURRENT_DATE + INTERVAL '1 day');

-- =======================================================================
-- 3. INTELLIGENCE TABLES
-- =======================================================================

CREATE TABLE IF NOT EXISTS devices (
    device_id SERIAL PRIMARY KEY,
    mac_address MACADDR NOT NULL UNIQUE,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    friendly_name TEXT
);

CREATE TABLE IF NOT EXISTS device_fingerprints (
    id SERIAL PRIMARY KEY,
    device_id INT REFERENCES devices(device_id) ON DELETE CASCADE,
    fingerprint_type TEXT NOT NULL,
    fingerprint_value TEXT NOT NULL,
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (device_id, fingerprint_type, fingerprint_value)
);

CREATE TABLE IF NOT EXISTS blocked_ips (
    id SERIAL PRIMARY KEY,
    ip_address INET NOT NULL UNIQUE,
    blocked_at TIMESTAMPTZ DEFAULT NOW(),
    blocked_by TEXT NOT NULL,
    reason TEXT,
    active BOOLEAN DEFAULT TRUE
);

-- =======================================================================
-- 4. PERFORMANCE INDEXES
-- =======================================================================
-- BRIN for Time (Massive storage savings)
CREATE INDEX IF NOT EXISTS idx_conn_ts_brin ON connections USING BRIN(ts);
CREATE INDEX IF NOT EXISTS idx_alerts_ts_brin ON alerts USING BRIN(timestamp);

-- B-Tree for Standard IP Lookups
CREATE INDEX IF NOT EXISTS idx_conn_src_ip ON connections(source_ip);
CREATE INDEX IF NOT EXISTS idx_conn_dst_ip ON connections(destination_ip);

-- NEW: GIN Indexes for Rich Data Search
-- Allows queries like: SELECT * FROM alerts WHERE details @> '{"payload": "..."}'
CREATE INDEX IF NOT EXISTS idx_conn_details_gin ON connections USING GIN(details);
CREATE INDEX IF NOT EXISTS idx_alerts_details_gin ON alerts USING GIN(details);