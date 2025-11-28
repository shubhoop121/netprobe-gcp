import os
import time
import subprocess
import psycopg2
import psycopg2.extras
import sys
import json
import threading
from datetime import datetime
from google.cloud import secretmanager

DB_NAME = os.environ.get('DB_NAME', 'netprobe_logs')
DB_USER = os.environ.get('DB_USER', 'netprobe_user')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
PROJECT_ID = "netprobe-473119"

ZEEK_LOG = "/opt/zeek/logs/current/conn.log"
SURICATA_LOG = "/var/log/suricata/eve.json"
BATCH_SIZE = 100
FLUSH_INTERVAL = 5

# --- Database Helpers ---

def get_db_host_and_connect():
    """
    Fetches the latest IP from Secret Manager AND connects.
    We do this together so that if connection fails, we re-fetch the IP
    on the next try (solving the stale IP race condition).
    """
    client = secretmanager.SecretManagerServiceClient()
    secret_name = f"projects/{PROJECT_ID}/secrets/db-private-ip-live/versions/latest"
    
    # Retry loop for getting the secret AND connecting
    while True:
        db_host = None
        try:
            # 1. Fetch the Secret (Fresh every time)
            print(f"[{time.ctime()}] Fetching DB_HOST secret...")
            resp = client.access_secret_version(request={"name": secret_name})
            db_host = resp.payload.data.decode("UTF-8").strip()
            
            if not db_host:
                raise ValueError("Secret was empty")

            print(f"[{time.ctime()}] Got DB_HOST: {db_host}. Connecting...")

            # 2. Try to Connect
            conn = psycopg2.connect(
                host=db_host, 
                dbname=DB_NAME, 
                user=DB_USER, 
                password=DB_PASSWORD,
                connect_timeout=10 # Fail fast if IP is wrong
            )
            print(f"[{time.ctime()}] Connected successfully to {db_host}.")
            return conn

        except Exception as e:
            # If we fail (wrong IP, DB not ready, Secret not ready), we wait and loop.
            # This forces a RE-FETCH of the secret on the next loop.
            print(f"[{time.ctime()}] Connection/Secret failed (Host: {db_host}): {e}", file=sys.stderr)
            print(f"[{time.ctime()}] Retrying in 10s...", file=sys.stderr)
            time.sleep(10)

# --- Worker Class ---
class LogTailingWorker(threading.Thread):
    # REMOVED db_host from init. We fetch it dynamically now.
    def __init__(self, log_file, parser_func, insert_func, table_name):
        super().__init__()
        self.log_file = log_file
        self.parser_func = parser_func
        self.insert_func = insert_func
        self.table_name = table_name
        self.daemon = True 

    def run(self):
        while True:
            print(f"[{self.table_name}-Worker] Starting tail on {self.log_file}")
            conn = None
            try:
                # --- FIX: Fetch Secret + Connect inside the loop ---
                conn = get_db_host_and_connect()
                cursor = conn.cursor()
                
                batch = []
                last_flush = time.time()

                proc = subprocess.Popen(['tail', '-F', '-n', '0', self.log_file], 
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                
                for line in iter(proc.stdout.readline, b''):
                    line_str = line.decode('utf-8', errors='ignore').strip()
                    if not line_str or line_str.startswith('#'): continue

                    record = self.parser_func(line_str)
                    if record:
                        batch.append(record)

                    if len(batch) >= BATCH_SIZE or (time.time() - last_flush > FLUSH_INTERVAL and batch):
                        self.insert_func(cursor, batch)
                        conn.commit()
                        print(f"[{self.table_name}-Worker] Flushed {len(batch)} records.")
                        batch = []
                        last_flush = time.time()

            except Exception as e:
                print(f"!!! [{self.table_name}-Worker] CRASHED: {e}", file=sys.stderr)
                print(f"!!! [{self.table_name}-Worker] Retrying in 10 seconds...", file=sys.stderr)
                if conn:
                    try: conn.close()
                    except: pass
                time.sleep(10)
                # Loop restarts -> Calls get_db_host_and_connect() -> Refetch Secret

# --- Zeek Specifics ---
def parse_zeek(line):
    try:
        f = line.split('\t')
        if len(f) < 12: return None
        return (float(f[0]), f[1], f[2], int(f[3]), f[4], int(f[5]), f[6], f[7], 
                float(f[8]) if f[8] != '-' else None, 
                int(f[9]) if f[9] != '-' else None, 
                int(f[10]) if f[10] != '-' else None, f[11])
    except: return None

def insert_zeek(cursor, batch):
    sql = """
        INSERT INTO connections (
            ts, uid, source_ip, source_port, destination_ip, destination_port,
            proto, service, duration, orig_bytes, resp_bytes, conn_state
        ) VALUES %s ON CONFLICT DO NOTHING
    """
    tmpl = '(to_timestamp(%s), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)'
    psycopg2.extras.execute_values(cursor, sql, batch, template=tmpl, page_size=BATCH_SIZE)

# --- Suricata Specifics ---
def parse_suricata(line):
    try:
        log = json.loads(line)
        if log.get('event_type') != 'alert': return None
        
        alert_id = f"{log['flow_id']}-{log['in_iface']}-{log['timestamp']}"
        
        return (log['timestamp'], alert_id, log['src_ip'], log['dest_ip'], 
                log['alert']['signature_id'], log['alert']['signature'], log['alert']['severity'])
    except: return None

def insert_suricata(cursor, batch):
    sql = """
        INSERT INTO alerts (
            timestamp, alert_id, source_ip, destination_ip, signature_id, signature, severity
        ) VALUES %s ON CONFLICT DO NOTHING
    """
    tmpl = '(%s, %s, %s, %s, %s, %s, %s)'
    psycopg2.extras.execute_values(cursor, sql, batch, template=tmpl, page_size=BATCH_SIZE)

# --- Main ---
if __name__ == "__main__":
    print("--- NetProbe Omni-Shipper Starting ---")
    
    # We no longer fetch DB_HOST here. 
    # Each thread will fetch it independently and retry until it's correct.

    zeek_thread = LogTailingWorker(ZEEK_LOG, parse_zeek, insert_zeek, "Zeek")
    suricata_thread = LogTailingWorker(SURICATA_LOG, parse_suricata, insert_suricata, "Suricata")

    zeek_thread.start()
    suricata_thread.start()

    zeek_thread.join()
    suricata_thread.join()