-- =======================================================================
-- 1. LOGGING TABLES (High Velocity - Partitioned)
-- =======================================================================

-- CONNECTIONS
CREATE TABLE IF NOT EXISTS connections ( -- Added IF NOT EXISTS
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
    PRIMARY KEY (ts, uid)
) PARTITION BY RANGE (ts);

-- Partitions
CREATE TABLE IF NOT EXISTS connections_default PARTITION OF connections DEFAULT;

CREATE TABLE IF NOT EXISTS connections_yest PARTITION OF connections
    FOR VALUES FROM (CURRENT_DATE - INTERVAL '1 day') TO (CURRENT_DATE);

CREATE TABLE IF NOT EXISTS connections_today PARTITION OF connections
    FOR VALUES FROM (CURRENT_DATE) TO (CURRENT_DATE + INTERVAL '1 day');

-- ALERTS
CREATE TABLE IF NOT EXISTS alerts ( -- Added IF NOT EXISTS
    timestamp TIMESTAMPTZ NOT NULL,
    alert_id TEXT NOT NULL,
    source_ip INET NOT NULL,
    destination_ip INET NOT NULL,
    signature_id INT,
    signature TEXT,
    severity INT,
    PRIMARY KEY (timestamp, alert_id)
) PARTITION BY RANGE (timestamp);

CREATE TABLE IF NOT EXISTS alerts_default PARTITION OF alerts DEFAULT;
CREATE TABLE IF NOT EXISTS alerts_today PARTITION OF alerts
    FOR VALUES FROM (CURRENT_DATE) TO (CURRENT_DATE + INTERVAL '1 day');

-- =======================================================================
-- 2. INTELLIGENCE TABLES (Low Velocity - Normalized)
-- =======================================================================

-- DEVICES
CREATE TABLE IF NOT EXISTS devices ( -- Added IF NOT EXISTS
    device_id SERIAL PRIMARY KEY,
    mac_address MACADDR NOT NULL UNIQUE,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    friendly_name TEXT
);

-- FINGERPRINTS
CREATE TABLE IF NOT EXISTS device_fingerprints ( -- Added IF NOT EXISTS
    id SERIAL PRIMARY KEY,
    device_id INT REFERENCES devices(device_id) ON DELETE CASCADE,
    fingerprint_type TEXT NOT NULL,
    fingerprint_value TEXT NOT NULL,
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (device_id, fingerprint_type, fingerprint_value)
);

-- =======================================================================
-- 3. OPERATIONS TABLES
-- =======================================================================

-- BLOCKED_IPS
CREATE TABLE IF NOT EXISTS blocked_ips ( -- Added IF NOT EXISTS
    id SERIAL PRIMARY KEY,
    ip_address INET NOT NULL,
    blocked_at TIMESTAMPTZ DEFAULT NOW(),
    blocked_by TEXT NOT NULL,
    reason TEXT,
    active BOOLEAN DEFAULT TRUE
);

-- =======================================================================
-- 4. PERFORMANCE INDEXES
-- =======================================================================
CREATE INDEX IF NOT EXISTS idx_conn_ts_brin ON connections USING BRIN(ts);
CREATE INDEX IF NOT EXISTS idx_alerts_ts_brin ON alerts USING BRIN(timestamp);
CREATE INDEX IF NOT EXISTS idx_conn_src_ip ON connections(source_ip);
CREATE INDEX IF NOT EXISTS idx_conn_dst_ip ON connections(destination_ip);