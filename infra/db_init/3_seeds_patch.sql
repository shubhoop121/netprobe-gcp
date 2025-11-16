-- This script patches our seed data to link devices to their IPs,
-- which is required by the DeviceMap component.

INSERT INTO device_fingerprints (device_id, fingerprint_type, fingerprint_value, last_seen)
SELECT 
    device_id, 
    'internal_ip', 
    '10.0.2.15',  -- Assign this IP to the Developer Laptop
    NOW()
FROM devices WHERE friendly_name = 'Developer Laptop (MacBook)';

INSERT INTO device_fingerprints (device_id, fingerprint_type, fingerprint_value, last_seen)
SELECT 
    device_id, 
    'internal_ip', 
    '192.168.1.100', -- Assign this IP to the Finance Workstation
    NOW()
FROM devices WHERE friendly_name = 'Finance Workstation 1';

INSERT INTO device_fingerprints (device_id, fingerprint_type, fingerprint_value, last_seen)
SELECT 
    device_id, 
    'internal_ip', 
    '10.0.2.5', -- Assign this IP to the HR-iPad
    NOW()
FROM devices WHERE friendly_name = 'HR-iPad';