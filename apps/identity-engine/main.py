import os
import json
import logging
import time
import psycopg2
from psycopg2.extras import RealDictCursor
from google.cloud import secretmanager

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Database Connection ---
def get_db_conn():
    if not os.environ.get("DB_PASSWORD"):
        # Production: Fetch from Secret Manager
        project_id = os.environ.get("PROJECT_ID", "netprobe-473119")
        client = secretmanager.SecretManagerServiceClient()
        pwd_name = f"projects/{project_id}/secrets/db-password/versions/latest"
        ip_name = f"projects/{project_id}/secrets/db-private-ip-live/versions/latest"
        
        password = client.access_secret_version(request={"name": pwd_name}).payload.data.decode("UTF-8").strip()
        host = client.access_secret_version(request={"name": ip_name}).payload.data.decode("UTF-8").strip()
    else:
        # Local Dev
        password = os.environ.get("DB_PASSWORD")
        host = os.environ.get("DB_HOST")

    return psycopg2.connect(
        host=host,
        dbname=os.environ.get('DB_NAME', 'netprobe_logs'),
        user=os.environ.get('DB_USER', 'netprobe_user'),
        password=password
    )

# --- Core Logic: Sessionization (DHCP) ---
def process_dhcp(conn):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    logger.info("Scanning for new DHCP logs...")
    # Fetch logs where service is 'dhcp'
    cur.execute("""
        SELECT ts, source_ip, details 
        FROM connections 
        WHERE service = 'dhcp' 
          AND ts > (NOW() - INTERVAL '20 minutes')
        ORDER BY ts ASC
    """)
    logs = cur.fetchall()
    
    updates = 0
    for log in logs:
        details = log.get('details', {})
        
        # Match keys from shipper.py HEADERS['dhcp']
        mac = details.get('mac')
        hostname = details.get('host_name')
        vendor = details.get('fp_vendor_class')

        if not mac: continue

        try:
            # 1. UPSERT Device
            cur.execute("""
                INSERT INTO devices (mac_address, friendly_name, last_seen)
                VALUES (%s, %s, %s)
                ON CONFLICT (mac_address) DO UPDATE SET
                    friendly_name = COALESCE(EXCLUDED.friendly_name, devices.friendly_name),
                    last_seen = EXCLUDED.last_seen
                RETURNING device_id
            """, (mac, hostname, log['ts']))
            
            device_id = cur.fetchone()['device_id']

            # 2. Insert Vendor Fingerprint
            if vendor:
                cur.execute("""
                    INSERT INTO device_fingerprints (device_id, fingerprint_type, fingerprint_value, last_seen)
                    VALUES (%s, 'vendor_class', %s, %s)
                    ON CONFLICT (device_id, fingerprint_type, fingerprint_value) 
                    DO UPDATE SET last_seen = EXCLUDED.last_seen
                """, (device_id, vendor, log['ts']))

            # 3. Update IP History (Time Travel)
            # Close old leases
            cur.execute("""
                UPDATE ip_history 
                SET validity_range = tstzrange(lower(validity_range), %s)
                WHERE ip_address = %s 
                  AND upper(validity_range) IS NULL
                  AND device_id != %s
            """, (log['ts'], log['source_ip'], device_id))

            # Open new lease
            cur.execute("""
                INSERT INTO ip_history (device_id, ip_address, validity_range)
                VALUES (%s, %s, tstzrange(%s, NULL))
                ON CONFLICT DO NOTHING
            """, (device_id, log['source_ip'], log['ts']))
            
            updates += 1
        except Exception as e:
            logger.error(f"Error processing DHCP for MAC {mac}: {e}")
            conn.rollback()
            continue

    conn.commit()
    logger.info(f"Processed {len(logs)} DHCP logs. Updated {updates} devices.")

# --- Core Logic: Fingerprinting (HTTP & SSL) ---
def process_traffic_fingerprints(conn):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    logger.info("Scanning for HTTP/SSL fingerprints...")

    # We look for HTTP (User-Agent) OR SSL (JA3)
    # Using the single 'connections' stream
    cur.execute("""
        SELECT ts, source_ip, service, details
        FROM connections
        WHERE service IN ('http', 'ssl')
          AND ts > (NOW() - INTERVAL '15 minutes')
    """)
    logs = cur.fetchall()
    
    count = 0
    for log in logs:
        details = log.get('details', {})
        fingerprint_type = None
        fingerprint_value = None

        # Extract based on protocol
        if log['service'] == 'http':
            fingerprint_value = details.get('user_agent')
            fingerprint_type = 'user_agent'
        elif log['service'] == 'ssl':
            fingerprint_value = details.get('ja3')
            fingerprint_type = 'ja3'

        if not fingerprint_value: continue

        # Correlate IP -> Device ID using Time Travel
        try:
            cur.execute("""
                SELECT device_id FROM ip_history 
                WHERE ip_address = %s 
                  AND validity_range @> %s::timestamptz
                LIMIT 1
            """, (log['source_ip'], log['ts']))
            
            match = cur.fetchone()
            if match:
                # Found the device! Link the fingerprint.
                cur.execute("""
                    INSERT INTO device_fingerprints (device_id, fingerprint_type, fingerprint_value, last_seen)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (device_id, fingerprint_type, fingerprint_value) 
                    DO UPDATE SET last_seen = EXCLUDED.last_seen
                """, (match['device_id'], fingerprint_type, fingerprint_value, log['ts']))
                count += 1
        except Exception as e:
            logger.error(f"Error processing fingerprint: {e}")
            continue
    
    conn.commit()
    logger.info(f"Correlated {count} new fingerprints (User-Agent/JA3).")

if __name__ == "__main__":
    try:
        logger.info("--- Identity Engine Starting ---")
        conn = get_db_conn()
        
        # 1. Establish Identity (DHCP)
        process_dhcp(conn)
        
        # 2. Enrich Identity (HTTP/SSL)
        process_traffic_fingerprints(conn)
        
        conn.close()
        logger.info("--- Identity Engine Finished ---")
    except Exception as e:
        logger.fatal(f"Identity Engine Crashed: {e}")
        sys.exit(1)