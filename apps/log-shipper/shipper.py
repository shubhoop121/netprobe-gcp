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

# --- Configuration ---
DB_NAME = os.environ.get('DB_NAME', 'netprobe_logs')
DB_USER = os.environ.get('DB_USER', 'netprobe_user')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
PROJECT_ID = "netprobe-473119"

ZEEK_BASE = "/opt/zeek/logs/current"
LOG_FILES = {
    "conn": f"{ZEEK_BASE}/conn.log",
    "dhcp": f"{ZEEK_BASE}/dhcp.log",
    "ssl": f"{ZEEK_BASE}/ssl.log",
    "http": f"{ZEEK_BASE}/http.log",
    "dns": f"{ZEEK_BASE}/dns.log",   # NEW: For mDNS
    "ntlm": f"{ZEEK_BASE}/ntlm.log", # NEW: For Windows Hostnames
    "suricata": "/var/log/suricata/eve.json"
}

BATCH_SIZE = 100
FLUSH_INTERVAL = 5

# --- HEADERS (Updated for Research v2.1) ---
HEADERS = {
    "conn": ["ts", "uid", "id.orig_h", "id.orig_p", "id.resp_h", "id.resp_p", "proto", "service", "duration", "orig_bytes", "resp_bytes", "conn_state"],
    "dhcp": ["ts", "uids", "client_addr", "server_addr", "mac", "host_name", "client_fqdn", "domain", "requested_addr", "assigned_addr", "lease_time", "client_message", "server_message", "msg_types", "duration", "fp_vendor_class", "fp_param_list", "fp_circuit_id", "fp_remote_id"],
    # Updated for JA4
    "ssl": ["ts", "uid", "id.orig_h", "id.orig_p", "id.resp_h", "id.resp_p", "version", "cipher", "curve", "server_name", "resumed", "last_alert", "next_protocol", "established", "ssl_history", "cert_chain_fps", "client_cert_chain_fps", "sni_matches_cert", "validation_status", "ja3", "ja3s", "ja4", "ja4s"],
    "http": ["ts", "uid", "id.orig_h", "id.orig_p", "id.resp_h", "id.resp_p", "trans_depth", "method", "host", "uri", "referrer", "user_agent"],
    # NEW: DNS Headers
    "dns": ["ts", "uid", "id.orig_h", "id.orig_p", "id.resp_h", "id.resp_p", "proto", "trans_id", "rtt", "query", "qclass", "qclass_name", "qtype", "qtype_name", "rcode", "rcode_name", "AA", "TC", "RD", "RA", "Z", "answers", "TTLs", "rejected"],
    # NEW: NTLM Headers (Critical for Windows)
    "ntlm": ["ts", "uid", "id.orig_h", "id.orig_p", "id.resp_h", "id.resp_p", "username", "hostname", "domainname", "server_nb_computer_name", "server_dns_computer_name", "server_tree_name", "success"]
}

# --- Database Helpers ---
def get_db_host_and_connect():
    client = secretmanager.SecretManagerServiceClient()
    secret_name = f"projects/{PROJECT_ID}/secrets/db-private-ip-live/versions/latest"
    while True:
        try:
            resp = client.access_secret_version(request={"name": secret_name})
            db_host = resp.payload.data.decode("UTF-8").strip()
            conn = psycopg2.connect(
                host=db_host, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD, connect_timeout=10
            )
            print(f"[{time.ctime()}] Connected to DB: {db_host}")
            return conn
        except Exception as e:
            print(f"[{time.ctime()}] DB Connection failed: {e}. Retrying in 10s...", file=sys.stderr)
            time.sleep(10)

# --- Worker Class ---
class LogTailingWorker(threading.Thread):
    def __init__(self, log_file, log_type, insert_func):
        super().__init__()
        self.log_file = log_file
        self.log_type = log_type
        self.insert_func = insert_func
        self.daemon = True 

    def run(self):
        while True:
            print(f"[{self.log_type}-Worker] Starting tail on {self.log_file}")
            conn = None
            try:
                conn = get_db_host_and_connect()
                cursor = conn.cursor()
                batch = []
                last_flush = time.time()
                proc = subprocess.Popen(['tail', '-F', '-n', '0', self.log_file], 
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                
                for line in iter(proc.stdout.readline, b''):
                    line_str = line.decode('utf-8', errors='ignore').strip()
                    if not line_str or line_str.startswith('#'): continue

                    record = parse_zeek_generic(line_str, self.log_type)
                    if record:
                        batch.append(record)

                    if len(batch) >= BATCH_SIZE or (time.time() - last_flush > FLUSH_INTERVAL and batch):
                        self.insert_func(cursor, batch)
                        conn.commit()
                        batch = []
                        last_flush = time.time()
            except Exception as e:
                print(f"!!! [{self.log_type}-Worker] CRASHED: {e}", file=sys.stderr)
                time.sleep(10)

# --- Parsing Logic ---
def parse_zeek_generic(line, log_type):
    try:
        f = line.split('\t')
        headers = HEADERS.get(log_type, [])
        
        details = {}
        for i, key in enumerate(headers):
            if i < len(f) and f[i] != '-':
                details[key] = f[i]
        
        details_json = json.dumps(details)

        # Map to 'connections' table columns
        if log_type == 'conn':
            return (float(f[0]), f[1], f[2], int(f[3]), f[4], int(f[5]), f[6], f[7], 
                    float(f[8]) if f[8] != '-' else None, 
                    int(f[9]) if f[9] != '-' else None, 
                    int(f[10]) if f[10] != '-' else None, f[11], details_json)
        
        # For other logs (DHCP, SSL, HTTP, DNS, NTLM), we map common fields (IPs/Ports) 
        # and rely on 'details' for the rest.
        elif log_type in ['ssl', 'http', 'dns', 'ntlm']:
             return (float(f[0]), f[1], f[2], int(f[3]), f[4], int(f[5]), 'tcp', log_type, 
                    0.0, 0, 0, 'SF', details_json)
        
        elif log_type == 'dhcp':
            uid = f[1].split(',')[0] if len(f) > 1 else 'dhcp'
            return (float(f[0]), uid, f[2], 67, f[3], 67, 'udp', 'dhcp', 
                    0.0, 0, 0, 'SF', details_json)

    except Exception:
        return None

def insert_zeek(cursor, batch):
    sql = """
        INSERT INTO connections (
            ts, uid, source_ip, source_port, destination_ip, destination_port,
            proto, service, duration, orig_bytes, resp_bytes, conn_state, details
        ) VALUES %s ON CONFLICT DO NOTHING
    """
    tmpl = '(to_timestamp(%s), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)'
    psycopg2.extras.execute_values(cursor, sql, batch, template=tmpl, page_size=BATCH_SIZE)

def parse_suricata(line):
    try:
        log = json.loads(line)
        if log.get('event_type') != 'alert': return None
        alert_id = f"{log['flow_id']}-{log['in_iface']}-{log['timestamp']}"
        details_json = json.dumps(log) 
        return (log['timestamp'], alert_id, log['src_ip'], log['dest_ip'], 
                log['alert']['signature_id'], log['alert']['signature'], log['alert']['severity'], details_json)
    except: return None

def insert_suricata(cursor, batch):
    sql = """
        INSERT INTO alerts (
            timestamp, alert_id, source_ip, destination_ip, signature_id, signature, severity, details
        ) VALUES %s ON CONFLICT DO NOTHING
    """
    tmpl = '(%s, %s, %s, %s, %s, %s, %s, %s)'
    psycopg2.extras.execute_values(cursor, sql, batch, template=tmpl, page_size=BATCH_SIZE)

if __name__ == "__main__":
    print("--- NetProbe Omni-Shipper Starting ---")
    threads = []
    threads.append(LogTailingWorker(LOG_FILES['suricata'], "suricata", insert_suricata))
    
    for log_type, path in LOG_FILES.items():
        if log_type == "suricata": continue
        threads.append(LogTailingWorker(path, log_type, insert_zeek))

    for t in threads: t.start()
    for t in threads: t.join()