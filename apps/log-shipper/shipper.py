import os
import time
import subprocess
import psycopg2
import psycopg2.extras
import sys
import argparse
from google.cloud import secretmanager # --- CHANGE 1: Add Google Secret Manager ---

# --- CHANGE 2: Remove global DB_HOST, add PROJECT_ID ---
DB_NAME = os.environ.get('DB_NAME', 'netprobe_logs')
DB_USER = os.environ.get('DB_USER', 'netprobe_user')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
PROJECT_ID = "netprobe-473119" # You can also get this from metadata server

# Constants
LOG_FILE_PATH_DEFAULT = "/opt/zeek/logs/current/conn.log"
BATCH_SIZE = 100
FLUSH_INTERVAL = 5

# --- CHANGE 3: Add new function to get host IP ---
def get_db_host_from_secret():
    """
    Fetches the live DB host IP from Secret Manager.
    This function will block and retry until it succeeds,
    solving the NVA startup race condition.
    """
    client = secretmanager.SecretManagerServiceClient()
    secret_name = f"projects/{PROJECT_ID}/secrets/db-private-ip-live/versions/latest"
    
    while True:
        try:
            print(f"[{time.ctime()}] Attempting to fetch 'db-private-ip-live' secret...")
            response = client.access_secret_version(request={"name": secret_name})
            db_host = response.payload.data.decode("UTF-8").strip()
            
            # Check for valid, non-dummy IP
            if db_host and db_host != "dummy_ip_for_plan" and db_host != "":
                print(f"[{time.ctime()}] Successfully fetched DB_HOST: {db_host}")
                return db_host
            else:
                raise ValueError(f"Fetched invalid or dummy IP: '{db_host}'")
        except Exception as e:
            print(f"[{time.ctime()}] Failed to fetch DB_HOST ({e}). Retrying in 10s...", file=sys.stderr)
            time.sleep(10)

# --- CHANGE 4: Modify get_db_connection ---
def get_db_connection(db_host): # Pass in the host
    """Establishes a connection to the PostgreSQL database with retries."""
    conn = None
    while not conn:
        try:
            if not DB_PASSWORD:
                raise ValueError("DB_PASSWORD environment variable not set.")
            conn = psycopg2.connect(
                host=db_host, # Use the passed-in host
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD
            )
            print(f"[{time.ctime()}] Successfully connected to database '{db_host}'.")
            return conn
        except psycopg2.OperationalError as e:
            print(f"[{time.ctime()}] Connection failed: {e}. Retrying in 5 seconds...", file=sys.stderr)
            time.sleep(5)

def parse_zeek_conn_log(line):
    """
    Parses a tab-separated line from Zeek's conn.log.
    NOTE: This parser assumes the default field order of Zeek's conn.log.
    A more robust version could read the #fields header to map columns dynamically.
    """
    try:
        fields = line.strip().split('\t')
        if len(fields) < 12:
            return None # Not a valid conn.log line
            
        record = (
            float(fields[0]), # ts
            fields[1],        # uid
            fields[2],        # source_ip
            int(fields[3]),   # source_port
            fields[4],        # destination_ip
            int(fields[5]),   # destination_port
            fields[6],        # proto
            fields[7],        # service
            float(fields[8]) if fields[8] != '-' else None,   # duration
            int(fields[9]) if fields[9] != '-' else None,     # orig_bytes
            int(fields[10]) if fields[10] != '-' else None,   # resp_bytes
            fields[11],       # conn_state
        )
        return record
    except (IndexError, ValueError) as e:
        print(f"[{time.ctime()}] Skipping malformed log line: {line.strip()} | Error: {e}", file=sys.stderr)
        return None

def insert_batch(cursor, batch):
    """Inserts a batch of records using psycopg2.extras.execute_values with a template."""
    if not batch:
        return

    sql = """
        INSERT INTO connections (
            ts, uid, source_ip, source_port, destination_ip, destination_port,
            proto, service, duration, orig_bytes, resp_bytes, conn_state
        ) VALUES %s ON CONFLICT (uid) DO NOTHING;
    """
    template = '(to_timestamp(%s), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)'

    try:
        psycopg2.extras.execute_values(
            cursor,
            sql,
            batch,
            template=template,
            page_size=BATCH_SIZE
        )
        cursor.connection.commit()
        print(f"[{time.ctime()}] Successfully inserted/skipped batch of {len(batch)} records.")

    except Exception as e:
        print(f"[{time.ctime()}] Database batch insert failed: {e}", file=sys.stderr)
        cursor.connection.rollback()

# --- CHANGE 5: Modify main() ---
def main(log_file_path):
    """Main function to tail the log and ship data to the database."""
    
    # First, block until we get the real DB host IP
    db_host = get_db_host_from_secret()
    
    # Now, connect to the database
    conn = get_db_connection(db_host)
    cursor = conn.cursor()

    record_batch = []
    last_flush_time = time.time()

    try:
        process = subprocess.Popen(['tail', '-F', '-n', '0', log_file_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print(f"[{time.ctime()}] Tailing log file: {log_file_path}")

        for line_bytes in iter(process.stdout.readline, b''):
            line_str = line_bytes.decode('utf-8', errors='ignore')

            if line_str.startswith('#'):
                continue

            record = parse_zeek_conn_log(line_str)
            if record:
                record_batch.append(record)

            # Flush the batch if it's full or if the flush interval has passed
            if len(record_batch) >= BATCH_SIZE or (time.time() - last_flush_time > FLUSH_INTERVAL and record_batch):
                insert_batch(cursor, record_batch)
                conn.commit()
                record_batch = []
                last_flush_time = time.time()

    except KeyboardInterrupt:
        print(f"\n[{time.ctime()}] Shutting down. Flushing final batch...")
        insert_batch(cursor, record_batch)
        conn.commit()
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
        print(f"[{time.ctime()}] Database connection closed. Exiting.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ship Zeek conn.log to PostgreSQL.")
    parser.add_argument('--file', type=str, default=LOG_FILE_PATH_DEFAULT,
                        help=f"Path to the log file to tail. Defaults to {LOG_FILE_PATH_DEFAULT}")
    args = parser.parse_args()
    main(args.file)