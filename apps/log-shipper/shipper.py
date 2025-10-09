import os
import time
import subprocess
import psycopg2
import psycopg2.extras
import sys
import argparse

# --- Configuration ---
# Credentials and host are read from environment variables for security
DB_HOST = os.environ.get('DB_HOST', 'db') # Defaults to 'db' for local Docker
DB_NAME = os.environ.get('DB_NAME', 'netprobe_logs_local')
DB_USER = os.environ.get('DB_USER', 'netprobe_user')
DB_PASSWORD = os.environ.get('DB_PASSWORD')

# Constants
LOG_FILE_PATH_DEFAULT = "/opt/zeek/logs/current/conn.log"
BATCH_SIZE = 100
FLUSH_INTERVAL = 5 # seconds

def get_db_connection():
    """Establishes a connection to the PostgreSQL database with retries."""
    conn = None
    while not conn:
        try:
            if not DB_PASSWORD:
                raise ValueError("DB_PASSWORD environment variable not set.")
            conn = psycopg2.connect(
                host=DB_HOST,
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD
            )
            print(f"[{time.ctime()}] Successfully connected to database '{DB_HOST}'.")
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
    """Inserts a batch of records using psycopg2.extras.execute_values for high efficiency."""
    if not batch:
        return
        
    sql = """
        INSERT INTO connections (
            ts, uid, source_ip, source_port, destination_ip, destination_port,
            proto, service, duration, orig_bytes, resp_bytes, conn_state
        ) VALUES %s ON CONFLICT (uid) DO NOTHING;
    """
    try:
        psycopg2.extras.execute_values(cursor, sql, batch)
        print(f"[{time.ctime()}] Successfully inserted batch of {len(batch)} records.")
    except Exception as e:
        print(f"[{time.ctime()}] Database batch insert failed: {e}", file=sys.stderr)
        # In a real production system, you might handle failed batches (e.g., write to a dead-letter file)
        pass

def main(log_file_path):
    """Main function to tail the log and ship data to the database."""
    conn = get_db_connection()
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