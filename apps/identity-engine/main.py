import os
import json
import sys
import logging
import time
import psycopg2
from psycopg2.extras import RealDictCursor
from google.cloud import secretmanager

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Database Connection ---
def get_db_conn():
    # ... (Keep your existing connection logic) ...
    if not os.environ.get("DB_PASSWORD"):
        project_id = os.environ.get("PROJECT_ID", "netprobe-473119")
        client = secretmanager.SecretManagerServiceClient()
        pwd_name = f"projects/{project_id}/secrets/db-password/versions/latest"
        ip_name = f"projects/{project_id}/secrets/db-private-ip-live/versions/latest"
        password = client.access_secret_version(request={"name": pwd_name}).payload.data.decode("UTF-8").strip()
        host = client.access_secret_version(request={"name": ip_name}).payload.data.decode("UTF-8").strip()
    else:
        password = os.environ.get("DB_PASSWORD")
        host = os.environ.get("DB_HOST")

    return psycopg2.connect(
        host=host,
        dbname=os.environ.get('DB_NAME', 'netprobe_logs'),
        user=os.environ.get('DB_USER', 'netprobe_user'),
        password=password
    )

# --- Core Logic: Identity Resolution (DHCP) ---
def process_dhcp(conn):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    logger.info("Scanning for new DHCP logs...")
    
    cur.execute("""
        SELECT ts, source_ip, details 
        FROM connections 
        WHERE service = 'dhcp' 
          AND ts > (NOW() - INTERVAL '24 HOURS')
        ORDER BY ts ASC
    """)
    logs = cur.fetchall()
    
    updates = 0
    for log in logs:
        details = log.get('details', {})
        
        mac = details.get('mac')
        hostname = details.get('host_name')
        vendor = details.get('fp_vendor_class')
        # NEW: Extract Client ID (Option 61)
        client_id = details.get('fp_client_id')

        if not mac: continue

        try:
            # 1. UPSERT Device
            # We now also save the Client ID
            cur.execute("""
                INSERT INTO devices (primary_mac, friendly_name, client_id_opt61, last_seen)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (primary_mac) DO UPDATE SET
                    friendly_name = COALESCE(EXCLUDED.friendly_name, devices.friendly_name),
                    client_id_opt61 = COALESCE(EXCLUDED.client_id_opt61, devices.client_id_opt61),
                    last_seen = EXCLUDED.last_seen
                RETURNING device_uuid
            """, (mac, hostname, client_id, log['ts']))
            
            device_uuid = cur.fetchone()['device_uuid']

            # 2. Vendor Fingerprint
            if vendor and vendor != '-':
                cur.execute("""
                    INSERT INTO device_fingerprints (device_uuid, fingerprint_type, fingerprint_value, last_seen)
                    VALUES (%s, 'vendor_class', %s, %s)
                    ON CONFLICT (device_uuid, fingerprint_type, fingerprint_value) 
                    DO UPDATE SET last_seen = EXCLUDED.last_seen
                """, (device_uuid, vendor, log['ts']))

            # 3. Time Travel (IP History)
            cur.execute("""
                UPDATE ip_history 
                SET validity_range = tstzrange(lower(validity_range), %s)
                WHERE ip_address = %s 
                  AND upper(validity_range) IS NULL
                  AND device_uuid != %s
            """, (log['ts'], log['source_ip'], device_uuid))

            cur.execute("""
                INSERT INTO ip_history (device_uuid, ip_address, validity_range)
                VALUES (%s, %s, tstzrange(%s, NULL))
                ON CONFLICT DO NOTHING
            """, (device_uuid, log['source_ip'], log['ts']))
            
            updates += 1
        except Exception as e:
            logger.error(f"Error processing DHCP for MAC {mac}: {e}")
            conn.rollback()
            continue

    conn.commit()
    logger.info(f"DHCP: Processed {len(logs)} logs. Updated {updates} devices.")

def process_secondary_names(conn):
    """
    Scans NTLM and mDNS logs to find hostnames for devices that hid them in DHCP.
    """
    cur = conn.cursor(cursor_factory=RealDictCursor)
    logger.info("Scanning for Secondary Names (NTLM/mDNS)...")

    # Look for NTLM (Windows Names) or DNS (mDNS .local names)
    cur.execute("""
        SELECT ts, source_ip, service, details
        FROM connections
        WHERE service IN ('ntlm', 'dns')
          AND ts > (NOW() - INTERVAL '20 minutes')
    """)
    logs = cur.fetchall()
    
    updates = 0
    for log in logs:
        details = log.get('details', {})
        found_name = None
        source_type = None

        # NTLM Extraction
        if log['service'] == 'ntlm':
            found_name = details.get('hostname')
            source_type = 'NTLM'

        # mDNS Extraction (Zeek dns.log)
        elif log['service'] == 'dns':
            query = details.get('query', '')
            if query and query.endswith('.local'):
                found_name = query
                source_type = 'mDNS'

        # Guard clause: Skip if name empty OR source_type undefined
        if not found_name or found_name == '-' or not source_type: 
            continue

        try:
            # Find who had this IP at this time
            cur.execute("""
                SELECT device_uuid FROM ip_history 
                WHERE ip_address = %s 
                  AND validity_range @> %s::timestamptz
                LIMIT 1
            """, (log['source_ip'], log['ts']))
            
            match = cur.fetchone()
            if match:
                # Update the device name if it's currently empty or generic
                cur.execute("""
                    UPDATE devices 
                    SET current_hostname = %s, hostname_source = %s
                    WHERE device_uuid = %s 
                      AND (current_hostname IS NULL OR current_hostname = '')
                """, (found_name, source_type, match['device_uuid']))
                
                if cur.rowcount > 0:
                    updates += 1
        except Exception as e:
            continue

    conn.commit()
    # FIX: Removed {source_type} variable from here to avoid UnboundLocalError
    logger.info(f"Names: Found {updates} new hostnames via NTLM/mDNS.")

# --- Core Logic: Fingerprinting (HTTP & SSL) ---
def process_traffic_fingerprints(conn):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    logger.info("Scanning for HTTP/SSL fingerprints...")

    cur.execute("""
        SELECT ts, source_ip, service, details
        FROM connections
        WHERE service IN ('http', 'ssl')
          AND ts > (NOW() - INTERVAL '24 HOURS')
    """)
    logs = cur.fetchall()
    
    count = 0
    for log in logs:
        details = log.get('details', {})
        fingerprint_type = None
        fingerprint_value = None

        if log['service'] == 'http':
            fingerprint_value = details.get('user_agent')
            fingerprint_type = 'user_agent'
        elif log['service'] == 'ssl':
            fingerprint_value = details.get('ja4') 
            fingerprint_type = 'ja4'

        if not fingerprint_value or fingerprint_value == '-': continue

        try:
            cur.execute("""
                SELECT device_uuid FROM ip_history 
                WHERE ip_address = %s 
                  AND validity_range @> %s::timestamptz
                LIMIT 1
            """, (log['source_ip'], log['ts']))
            
            match = cur.fetchone()
            if match:
                cur.execute("""
                    INSERT INTO device_fingerprints (device_uuid, fingerprint_type, fingerprint_value, last_seen)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (device_uuid, fingerprint_type, fingerprint_value) 
                    DO UPDATE SET last_seen = EXCLUDED.last_seen
                """, (match['device_uuid'], fingerprint_type, fingerprint_value, log['ts']))
                count += 1
        except Exception:
            continue
    
    conn.commit()
    logger.info(f"Fingerprints: Correlated {count} new items.")

if __name__ == "__main__":
    try:
        logger.info("--- Identity Engine Starting ---")
        conn = get_db_conn()
        process_dhcp(conn)
        process_secondary_names(conn) # Run the new logic
        process_traffic_fingerprints(conn)
        conn.close()
        logger.info("--- Identity Engine Finished ---")
    except Exception as e:
        logger.fatal(f"Identity Engine Crashed: {e}")
        sys.exit(1)