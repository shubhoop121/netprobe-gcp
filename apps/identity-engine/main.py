import os
import json
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from google.cloud import secretmanager

# Configure Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Database Connection (Reused pattern) ---
def get_db_conn():
    if os.environ.get("DB_PASSWORD"):
        password = os.environ.get("DB_PASSWORD")
        host = os.environ.get("DB_HOST")
    else:
        # Production: Fetch from Secret Manager
        project_id = os.environ.get("PROJECT_ID", "netprobe-473119")
        client = secretmanager.SecretManagerServiceClient()
        pwd_name = f"projects/{project_id}/secrets/db-password/versions/latest"
        ip_name = f"projects/{project_id}/secrets/db-private-ip-live/versions/latest"
        password = client.access_secret_version(request={"name": pwd_name}).payload.data.decode("UTF-8").strip()
        host = client.access_secret_version(request={"name": ip_name}).payload.data.decode("UTF-8").strip()

    return psycopg2.connect(
        host=host,
        dbname=os.environ.get('DB_NAME', 'netprobe_logs'),
        user=os.environ.get('DB_USER', 'netprobe_user'),
        password=password
    )

def process_dhcp_logs(conn):
    """
    Reads recent DHCP logs and updates the Device Inventory.
    Implements Research Section 5.1 (Sessionization).
    """
    logger.info("--- Starting DHCP Processing ---")
    cur = conn.cursor(cursor_factory=RealDictCursor)

    # 1. Fetch unproccessed DHCP logs from the last 15 minutes
    # We look inside the JSONB 'details' column for the specific fields we enabled in Zeek
    sql_fetch = """
        SELECT ts, source_ip, details 
        FROM connections 
        WHERE service = 'dhcp' 
          AND ts > (NOW() - INTERVAL '15 minutes')
        ORDER BY ts ASC
    """
    cur.execute(sql_fetch)
    logs = cur.fetchall()
    logger.info(f"Found {len(logs)} DHCP logs to process.")

    for log in logs:
        details = log.get('details', {})
        # Note: Depending on how Zeek dumps JSON, these keys might vary slightly.
        # We rely on the custom fields we added: host_name, mac (from L2 or client_id)
        
        # Zeek 'dhcp.log' usually puts the MAC in 'mac' or 'client_id'
        mac = details.get('mac') or details.get('client_id')
        hostname = details.get('host_name')
        
        if not mac:
            continue # Can't identify without MAC (for now)

        try:
            # 2. UPSERT Device (The Stable Entity)
            # Implements Research Section 4.2.1
            cur.execute("""
                INSERT INTO devices (mac_address, current_hostname, last_seen)
                VALUES (%s, %s, %s)
                ON CONFLICT (mac_address) DO UPDATE SET
                    current_hostname = COALESCE(EXCLUDED.current_hostname, devices.current_hostname),
                    last_seen = EXCLUDED.last_seen
                RETURNING device_id
            """, (mac, hostname, log['ts']))
            
            device_id = cur.fetchone()['device_id']

            # 3. UPDATE IP History (The Time Travel)
            # Implements Research Section 6.1 (Temporal Consistency)
            # "Close" any open lease for this IP that isn't us
            cur.execute("""
                UPDATE ip_history 
                SET validity_range = tstzrange(lower(validity_range), %s)
                WHERE ip_address = %s 
                  AND upper(validity_range) IS NULL
                  AND device_id != %s
            """, (log['ts'], log['source_ip'], device_id))

            # Insert new open-ended lease for us
            # We use 'tstzrange' with NULL upper bound (infinity) implies "currently active"
            cur.execute("""
                INSERT INTO ip_history (device_id, ip_address, validity_range)
                VALUES (%s, %s, tstzrange(%s, NULL))
                ON CONFLICT DO NOTHING
            """, (device_id, log['source_ip'], log['ts']))

        except Exception as e:
            logger.error(f"Failed to process log for MAC {mac}: {e}")
            conn.rollback()
            continue
    
    conn.commit()
    logger.info("--- DHCP Processing Complete ---")

def process_fingerprints(conn):
    """
    Scans HTTP/SSL logs to add metadata (User-Agent, JA3) to known IPs.
    Implements Research Section 5.4 (Process Traffic).
    """
    logger.info("--- Starting Fingerprint Correlation ---")
    cur = conn.cursor(cursor_factory=RealDictCursor)

    # Find HTTP logs with User-Agents
    cur.execute("""
        SELECT ts, source_ip, details->>'user_agent' as ua
        FROM connections
        WHERE service = 'http' 
          AND details->>'user_agent' IS NOT NULL
          AND ts > (NOW() - INTERVAL '15 minutes')
    """)
    http_logs = cur.fetchall()

    for log in http_logs:
        # Resolve IP to Device ID at that specific time (Time Travel Query)
        cur.execute("""
            SELECT device_id FROM ip_history 
            WHERE ip_address = %s 
              AND validity_range @> %s::timestamptz
            LIMIT 1
        """, (log['source_ip'], log['ts']))
        
        match = cur.fetchone()
        if match:
            # We found the device! Add the fingerprint.
            cur.execute("""
                INSERT INTO device_fingerprints (device_id, fingerprint_type, fingerprint_value, last_seen)
                VALUES (%s, 'user-agent', %s, %s)
                ON CONFLICT (device_id, fingerprint_type, fingerprint_value) 
                DO UPDATE SET last_seen = EXCLUDED.last_seen
            """, (match['device_id'], log['ua'], log['ts']))
    
    conn.commit()
    logger.info(f"Processed {len(http_logs)} HTTP fingerprints.")

if __name__ == "__main__":
    try:
        conn = get_db_conn()
        process_dhcp_logs(conn)
        process_fingerprints(conn)
        conn.close()
    except Exception as e:
        logger.fatal(f"Identity Engine Crashed: {e}")
        sys.exit(1)