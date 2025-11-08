-- =======================================================================
-- HELPER FUNCTION: RANDOM INT BETWEEN RANGE
-- =======================================================================
CREATE OR REPLACE FUNCTION random_between(low INT, high INT) RETURNS INT AS $$
BEGIN
   RETURN floor(random()* (high-low + 1) + low);
END;
$$ language 'plpgsql';

-- =======================================================================
-- SEED 1: DEVICES (Stable entities)
-- =======================================================================
INSERT INTO devices (mac_address, friendly_name) VALUES
    ('00:0c:29:6d:34:af', 'Developer Laptop (MacBook)'),
    ('00:50:56:c0:00:01', 'Finance Workstation 1'),
    ('00:50:56:c0:00:08', 'HR-iPad');

-- Link them to some fingerprints
INSERT INTO device_fingerprints (device_id, fingerprint_type, fingerprint_value)
SELECT device_id, 'user-agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
FROM devices WHERE friendly_name LIKE 'Developer%';

-- =======================================================================
-- SEED 2: MASSIVE CONNECTIONS LOG (10,000 rows)
-- =======================================================================
DO $$
DECLARE
    -- Fake internal IPs for our "network"
    src_ips INET[] := ARRAY['10.0.2.15', '10.0.2.50', '192.168.1.100', '10.0.2.5', '172.16.0.10'];
    -- Fake external IPs (Google, Cloudflare, malicious actors)
    dst_ips INET[] := ARRAY['8.8.8.8', '1.1.1.1', '142.250.1.1', '104.16.132.229', '45.10.15.20', '185.100.100.100'];
    -- Common services
    protocols TEXT[] := ARRAY['tcp', 'udp', 'icmp'];
    services TEXT[] := ARRAY['http', 'ssl', 'dns', 'ssh', '-'];
    
    i INT;
    chosen_proto TEXT;
    chosen_service TEXT;
    chosen_dport INT;
BEGIN
    FOR i IN 1..10000 LOOP
        -- Randomly pick protocol/service to make it look realistic
        chosen_service := services[random_between(1, array_length(services, 1))];
        
        CASE chosen_service
            WHEN 'http' THEN chosen_proto := 'tcp'; chosen_dport := 80;
            WHEN 'ssl'  THEN chosen_proto := 'tcp'; chosen_dport := 443;
            WHEN 'dns'  THEN chosen_proto := 'udp'; chosen_dport := 53;
            WHEN 'ssh'  THEN chosen_proto := 'tcp'; chosen_dport := 22;
            ELSE chosen_proto := protocols[random_between(1, array_length(protocols, 1))]; chosen_dport := random_between(1024, 65535);
        END CASE;

        INSERT INTO connections (
            ts, uid, source_ip, source_port, destination_ip, destination_port, 
            proto, service, duration, orig_bytes, resp_bytes, conn_state
        ) VALUES (
            NOW() - (random() * interval '7 days'), -- Random time in last 7 days
            md5(random()::text || clock_timestamp()::text), -- Random UID
            src_ips[random_between(1, array_length(src_ips, 1))],
            random_between(32000, 65000), -- Ephemeral source port
            dst_ips[random_between(1, array_length(dst_ips, 1))],
            chosen_dport,
            chosen_proto,
            chosen_service,
            random() * 5, -- duration 0-5s
            random_between(100, 10000), -- orig_bytes
            random_between(100, 100000), -- resp_bytes
            (ARRAY['SF', 'S0', 'OTH'])[random_between(1,3)] -- conn_state
        );
    END LOOP;
END $$;

-- =======================================================================
-- SEED 3: ALERTS (500 rows, skewed towards "malicious" IPs)
-- =======================================================================
DO $$
DECLARE
    -- Suspicious IPs from our list above
    attacker_ips INET[] := ARRAY['45.10.15.20', '185.100.100.100'];
    victim_ips INET[] := ARRAY['10.0.2.15', '192.168.1.100'];
    signatures TEXT[] := ARRAY['ET SCAN Potential SSH Scan', 'ET MALWARE Cobalt Strike Beacon', 'GPL ATTACK_RESPONSE id check returned root'];
    i INT;
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO alerts (
            timestamp, alert_id, source_ip, destination_ip, signature_id, signature, severity
        ) VALUES (
            NOW() - (random() * interval '7 days'),
            gen_random_uuid()::text,
            attacker_ips[random_between(1, array_length(attacker_ips, 1))],
            victim_ips[random_between(1, array_length(victim_ips, 1))],
            random_between(2000000, 2000999),
            signatures[random_between(1, array_length(signatures, 1))],
            random_between(1, 3) -- Severity 1 (High) to 3 (Low)
        );
    END LOOP;
END $$;