-- infra/db_init/1_schema.sql

-- =======================================================================
-- 0. EXTENSIONS
-- =======================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist; -- For Time Travel ranges
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- For Device UUIDs [Research 4.1.1]

-- =======================================================================
-- 1. LOGGING TABLES (Partitioned)
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
    details JSONB, -- Holds DNS queries, NTLM hostnames, JA4 hashes
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
-- 2. PARTITION MAINTENANCE
-- =======================================================================
CREATE TABLE IF NOT EXISTS connections_default PARTITION OF connections DEFAULT;
CREATE TABLE IF NOT EXISTS alerts_default PARTITION OF alerts DEFAULT;

DO $$
DECLARE
    days_ahead INT := 7;
    current_iter_date DATE;
    start_val TEXT; end_val TEXT; partition_name TEXT;
    table_list TEXT[] := ARRAY['connections', 'alerts'];
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY table_list LOOP
        FOR i IN 0..days_ahead LOOP
            current_iter_date := CURRENT_DATE + i;
            partition_name := tbl || '_' || to_char(current_iter_date, 'YYYY_MM_DD');
            start_val := to_char(current_iter_date, 'YYYY-MM-DD');
            end_val := to_char(current_iter_date + 1, 'YYYY-MM-DD');
            EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)', partition_name, tbl, start_val, end_val);
        END LOOP;
    END LOOP;
END $$;

-- =======================================================================
-- 3. INTELLIGENCE TABLES (Research v2.1 Compliant)
-- =======================================================================
DROP TABLE IF EXISTS device_fingerprints; -- Must drop child first
DROP TABLE IF EXISTS ip_history;          -- Must drop child first
DROP TABLE IF EXISTS devices;
-- DEVICES: The stable entity (Anchored by MAC)
CREATE TABLE IF NOT EXISTS devices (
    device_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- The "Hard Anchors"
    primary_mac MACADDR, 
    duid TEXT,              -- IPv6 Long-term anchor
    client_id_opt61 TEXT,   -- Windows Long-term anchor (THE MISSING COLUMN)
    
    -- Derived Attributes
    current_hostname TEXT,
    hostname_source TEXT,   -- 'DHCP', 'mDNS', 'NTLM'
    vendor_oui TEXT,
    os_family TEXT,
    
    -- Metadata
    is_randomized_mac BOOLEAN DEFAULT FALSE,
    confidence_score INTEGER DEFAULT 0,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(primary_mac)
);

-- FINGERPRINTS: Attributes linked to a device
CREATE TABLE IF NOT EXISTS device_fingerprints (
    fingerprint_id BIGSERIAL PRIMARY KEY,
    device_uuid UUID REFERENCES devices(device_uuid) ON DELETE CASCADE,
    
    fingerprint_type TEXT NOT NULL, 
    fingerprint_value TEXT NOT NULL,
    
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE (device_uuid, fingerprint_type, fingerprint_value)
);

-- IP HISTORY: The "Time Travel" table
CREATE TABLE IF NOT EXISTS ip_history (
    history_id BIGSERIAL PRIMARY KEY,
    device_uuid UUID REFERENCES devices(device_uuid) ON DELETE CASCADE,
    ip_address INET NOT NULL,
    validity_range TSTZRANGE NOT NULL,
    
    EXCLUDE USING GIST (
        ip_address WITH =,
        validity_range WITH &&
    )
);

-- =======================================================================
-- 4. OPERATIONS & INDEXES
-- =======================================================================
CREATE TABLE IF NOT EXISTS blocked_ips (
    id SERIAL PRIMARY KEY,
    ip_address INET NOT NULL UNIQUE,
    blocked_at TIMESTAMPTZ DEFAULT NOW(),
    blocked_by TEXT NOT NULL,
    reason TEXT,
    active BOOLEAN DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_conn_ts_brin ON connections USING BRIN(ts);
CREATE INDEX IF NOT EXISTS idx_alerts_ts_brin ON alerts USING BRIN(timestamp);
CREATE INDEX IF NOT EXISTS idx_conn_src_ip ON connections(source_ip);
CREATE INDEX IF NOT EXISTS idx_conn_dst_ip ON connections(destination_ip);
CREATE INDEX IF NOT EXISTS idx_conn_details_gin ON connections USING GIN(details);
CREATE INDEX IF NOT EXISTS idx_alerts_details_gin ON alerts USING GIN(details);

-- Intelligence Indexes
CREATE INDEX IF NOT EXISTS idx_devices_mac ON devices(primary_mac);
CREATE INDEX IF NOT EXISTS idx_ip_history_range ON ip_history USING GIST (validity_range);
CREATE INDEX IF NOT EXISTS idx_ip_history_ip ON ip_history (ip_address);