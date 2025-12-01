-- =======================================================================
-- 0. EXTENSIONS
-- =======================================================================
-- Required for the 'ip_history' table to handle overlapping time ranges.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- =======================================================================
-- 1. LOGGING TABLES (High Velocity - Partitioned)
-- =======================================================================

-- CONNECTIONS (Zeek Output)
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
    -- JSONB column for rich details (HTTP headers, DNS queries, etc.)
    details JSONB,
    PRIMARY KEY (ts, uid)
) PARTITION BY RANGE (ts);

-- ALERTS (Suricata Output)
CREATE TABLE IF NOT EXISTS alerts (
    timestamp TIMESTAMPTZ NOT NULL,
    alert_id TEXT NOT NULL,
    source_ip INET NOT NULL,
    destination_ip INET NOT NULL,
    signature_id INT,
    signature TEXT,
    severity INT,
    -- JSONB column for full raw alert payload
    details JSONB,
    PRIMARY KEY (timestamp, alert_id)
) PARTITION BY RANGE (timestamp);

-- =======================================================================
-- 2. PARTITION MAINTENANCE (Automatic Self-Healing)
-- =======================================================================

-- 2a. Create Default Partitions (Catch-all for unexpected dates)
CREATE TABLE IF NOT EXISTS connections_default PARTITION OF connections DEFAULT;
CREATE TABLE IF NOT EXISTS alerts_default PARTITION OF alerts DEFAULT;

-- 2b. Dynamic Partition Creation (Next 7 Days)
-- This block runs every time the schema is applied.
-- It ensures tables exist for Today through Next Week.
DO $$
DECLARE
    days_ahead INT := 7;
    current_iter_date DATE;
    start_val TEXT;
    end_val TEXT;
    partition_name TEXT;
    table_list TEXT[] := ARRAY['connections', 'alerts'];
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY table_list
    LOOP
        FOR i IN 0..days_ahead LOOP
            current_iter_date := CURRENT_DATE + i;
            
            -- Name format: connections_2025_11_30
            partition_name := tbl || '_' || to_char(current_iter_date, 'YYYY_MM_DD');
            
            -- Range: 00:00 today to 00:00 tomorrow
            start_val := to_char(current_iter_date, 'YYYY-MM-DD');
            end_val := to_char(current_iter_date + 1, 'YYYY-MM-DD');

            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
                partition_name, tbl, start_val, end_val
            );
        END LOOP;
    END LOOP;
END $$;

-- =======================================================================
-- 3. INTELLIGENCE TABLES (Device Map)
-- =======================================================================

-- DEVICES: The stable entity (Anchored by MAC)
CREATE TABLE IF NOT EXISTS devices (
    device_id SERIAL PRIMARY KEY,
    mac_address MACADDR NOT NULL UNIQUE,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    friendly_name TEXT
);

-- FINGERPRINTS: Attributes linked to a device (User-Agent, JA3)
CREATE TABLE IF NOT EXISTS device_fingerprints (
    id SERIAL PRIMARY KEY,
    device_id INT REFERENCES devices(device_id) ON DELETE CASCADE,
    fingerprint_type TEXT NOT NULL,
    fingerprint_value TEXT NOT NULL,
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (device_id, fingerprint_type, fingerprint_value)
);

-- IP HISTORY: The "Time Travel" table
-- Answer: "Who had IP X at Time T?"
CREATE TABLE IF NOT EXISTS ip_history (
    history_id BIGSERIAL PRIMARY KEY,
    device_id INT REFERENCES devices(device_id) ON DELETE CASCADE,
    ip_address INET NOT NULL,
    -- Stores the validity window [start, end)
    validity_range tstzrange NOT NULL,
    
    -- Constraint: No two devices can hold the same IP at the same time
    EXCLUDE USING gist (
        ip_address WITH =,
        validity_range WITH &&
    )
);

-- =======================================================================
-- 4. OPERATIONS TABLES
-- =======================================================================

-- BLOCKED_IPS: Audit log for the "Block IP" button
CREATE TABLE IF NOT EXISTS blocked_ips (
    id SERIAL PRIMARY KEY,
    ip_address INET NOT NULL UNIQUE,
    blocked_at TIMESTAMPTZ DEFAULT NOW(),
    blocked_by TEXT NOT NULL,
    reason TEXT,
    active BOOLEAN DEFAULT TRUE
);

-- =======================================================================
-- 5. PERFORMANCE INDEXES
-- =======================================================================

-- BRIN for Time (Massive storage savings for append-only logs)
CREATE INDEX IF NOT EXISTS idx_conn_ts_brin ON connections USING BRIN(ts);
CREATE INDEX IF NOT EXISTS idx_alerts_ts_brin ON alerts USING BRIN(timestamp);

-- B-Tree for Standard Lookups
CREATE INDEX IF NOT EXISTS idx_conn_src_ip ON connections(source_ip);
CREATE INDEX IF NOT EXISTS idx_conn_dst_ip ON connections(destination_ip);

-- GIN for JSONB (Deep search inside 'details')
CREATE INDEX IF NOT EXISTS idx_conn_details_gin ON connections USING GIN(details);
CREATE INDEX IF NOT EXISTS idx_alerts_details_gin ON alerts USING GIN(details);

-- GiST for Time Ranges (Fast overlap queries)
CREATE INDEX IF NOT EXISTS idx_ip_history_range ON ip_history USING GIST (validity_range);
CREATE INDEX IF NOT EXISTS idx_ip_history_ip ON ip_history (ip_address);