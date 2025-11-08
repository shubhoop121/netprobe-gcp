-- infra/db_init/1_schema.sql

-- =======================================================================
-- 1. LOGGING TABLES (High Velocity - Partitioned)
-- =======================================================================

-- CONNECTIONS: The core Zeek log. Partitioned by time (ts) for performance.
CREATE TABLE connections (
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
    PRIMARY KEY (ts, uid) -- Partition key MUST be part of the PK
) PARTITION BY RANGE (ts);

-- Create partitions for local development (e.g., 'yesterday' and 'today')
-- In production, pg_partman would handle this automatically.
CREATE TABLE connections_default PARTITION OF connections DEFAULT;

CREATE TABLE connections_yest PARTITION OF connections
    FOR VALUES FROM (CURRENT_DATE - INTERVAL '1 day') TO (CURRENT_DATE);

CREATE TABLE connections_today PARTITION OF connections
    FOR VALUES FROM (CURRENT_DATE) TO (CURRENT_DATE + INTERVAL '1 day');

-- ALERTS: Suricata output. Also likely high volume, so partitioned.
CREATE TABLE alerts (
    timestamp TIMESTAMPTZ NOT NULL,
    alert_id TEXT NOT NULL, -- UUID from Suricata
    source_ip INET NOT NULL,
    destination_ip INET NOT NULL,
    signature_id INT,
    signature TEXT,
    severity INT,
    PRIMARY KEY (timestamp, alert_id)
) PARTITION BY RANGE (timestamp);

CREATE TABLE alerts_default PARTITION OF alerts DEFAULT;
CREATE TABLE alerts_today PARTITION OF alerts
    FOR VALUES FROM (CURRENT_DATE) TO (CURRENT_DATE + INTERVAL '1 day');

-- =======================================================================
-- 2. INTELLIGENCE TABLES (Low Velocity - Normalized)
-- =======================================================================

-- DEVICES: Stable entities anchored by MAC address (from DHCP logs)
CREATE TABLE devices (
    device_id SERIAL PRIMARY KEY,
    mac_address MACADDR NOT NULL UNIQUE,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    friendly_name TEXT -- Can be manually edited by analysts later
);

-- FINGERPRINTS: Volatile observations linked to stable devices
CREATE TABLE device_fingerprints (
    id SERIAL PRIMARY KEY,
    device_id INT REFERENCES devices(device_id) ON DELETE CASCADE,
    fingerprint_type TEXT NOT NULL, -- e.g., 'ja3', 'user-agent', 'hostname'
    fingerprint_value TEXT NOT NULL,
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (device_id, fingerprint_type, fingerprint_value)
);

-- =======================================================================
-- 3. OPERATIONS TABLES
-- =======================================================================

-- BLOCKED_IPS: Audit trail for our "Active Response" feature
CREATE TABLE blocked_ips (
    id SERIAL PRIMARY KEY,
    ip_address INET NOT NULL,
    blocked_at TIMESTAMPTZ DEFAULT NOW(),
    blocked_by TEXT NOT NULL, -- e.g., 'user@company.com' or 'automated-rule'
    reason TEXT,
    active BOOLEAN DEFAULT TRUE
);

-- =======================================================================
-- 4. PERFORMANCE INDEXES (BRIN for time, B-Tree for lookups)
-- =======================================================================
-- BRIN indexes are amazing for these append-only time-series tables.
CREATE INDEX idx_conn_ts_brin ON connections USING BRIN(ts);
CREATE INDEX idx_alerts_ts_brin ON alerts USING BRIN(timestamp);

-- Standard B-Tree for common filter columns
CREATE INDEX idx_conn_src_ip ON connections(source_ip);
CREATE INDEX idx_conn_dst_ip ON connections(destination_ip);