import os
import sqlalchemy
import logging
from google.cloud import secretmanager
import base64
import json
from datetime import datetime
from psycopg2.extras import RealDictCursor
logger = logging.getLogger(__name__)
db = None

def get_db_password():
    """Fetches password from Env (Local) or Secret Manager (Prod)."""
    if os.environ.get("DB_PASSWORD"):
        return os.environ.get("DB_PASSWORD")

    # Production Fallback
    logger.info("--- Fetching DB_PASSWORD from Secret Manager ---")
    PROJECT_ID = os.environ.get("PROJECT_ID", "netprobe-473119")
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/db-password/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        logger.error(f"!!! CRITICAL: Secret Manager failure: {e}")
        return None

def init_connection_pool():
    DB_HOST = os.environ.get("DB_HOST")
    DB_USER = os.environ.get("DB_USER", "netprobe_user")
    DB_NAME = os.environ.get("DB_NAME", "netprobe_logs")
    
    if not DB_HOST:
        raise ValueError("DB_HOST not set.")

    db_pass = get_db_password()
    if not db_pass:
        raise ValueError("DB_PASSWORD could not be retrieved.")

    db_uri = sqlalchemy.engine.url.URL.create(
        drivername="postgresql+psycopg2",
        username=DB_USER,
        password=db_pass,
        host=DB_HOST,
        port=5432,
        database=DB_NAME,
    )
    
    return sqlalchemy.create_engine(db_uri, pool_size=5, pool_recycle=1800)

def get_db():
    """Lazy init of DB pool."""
    global db
    if db is None:
        logger.info("--- Initializing DB Pool... ---")
        db = init_connection_pool()
    return db

def init_app(app):
    """Register teardown/setup hooks if needed."""
    pass

# --- KEYSET PAGINATION HELPERS ---

def serialize_cursor(ts, uid):
    """
    Packs the sort keys (timestamp, uid) into a safe Base64 string.
    Format: JSON [ts_iso_string, uid] -> Base64
    """
    if not ts or not uid:
        return None
    
    ts_str = ts if isinstance(ts, str) else ts.isoformat()
    data = [ts_str, uid]
    json_str = json.dumps(data)
    return base64.urlsafe_b64encode(json_str.encode()).decode()

def deserialize_cursor(cursor_str):
    """
    Unpacks the cursor string back into Python objects.
    Returns: (datetime_obj, uid_str) or (None, None)
    """
    if not cursor_str:
        return None, None
    try:
        json_str = base64.urlsafe_b64decode(cursor_str.encode()).decode()
        ts_str, uid = json.loads(json_str)
        return datetime.fromisoformat(ts_str), uid
    except Exception as e:
        print(f"Invalid cursor format: {e}")
        return None, None

def get_logs_keyset(limit=50, cursor=None, filters=None):
    """
    High-Performance Log Fetcher.
    Uses tuple comparison (ts, uid) < (cursor_ts, cursor_uid) to seek.
    """
    pool = get_db()
    
    # 1. Parse the cursor (The "Bookmark")
    cursor_ts, cursor_uid = deserialize_cursor(cursor)

    # 2. Base Query
    sql = """
        SELECT ts, uid, source_ip, source_port, destination_ip, destination_port, 
               proto, service, duration, conn_state, details
        FROM connections
        WHERE 1=1
    """
    params = {}

    # 3. Apply Filters
    if filters:
        if filters.get('ip'):
            sql += " AND (source_ip = %(ip)s OR destination_ip = %(ip)s)"
            params['ip'] = filters['ip']
        if filters.get('service'):
            sql += " AND service = %(service)s"
            params['service'] = filters['service']
    
    # 4. Apply the Seek Logic
    if cursor_ts and cursor_uid:
        sql += " AND (ts, uid) < (%(cursor_ts)s, %(cursor_uid)s)"
        params['cursor_ts'] = cursor_ts
        params['cursor_uid'] = cursor_uid

    # 5. Order and Limit
    sql += " ORDER BY ts DESC, uid DESC LIMIT %(limit)s"
    params['limit'] = limit + 1

    logs = []
    next_cursor = None

    try:
        with pool.connect() as conn:
            # Access the raw DBAPI connection (psycopg2)
            raw_conn = conn.connection
            
            # --- THE FIX ---
            # Use try/finally instead of 'with' context manager for the cursor
            cur = raw_conn.cursor(cursor_factory=RealDictCursor)
            try:
                cur.execute(sql, params)
                rows = cur.fetchall()
                
                # Convert rows to list of dicts
                for row in rows:
                    row['ts'] = row['ts'].isoformat()
                    logs.append(dict(row))
            finally:
                cur.close() # Explicitly close the cursor
            # --- END FIX ---

        # 6. Handle Pagination Logic
        if len(logs) > limit:
            logs.pop() # Remove the extra row
            
            last_row = rows[limit-1]
            next_cursor = serialize_cursor(last_row['ts'], last_row['uid'])

        return {"logs": logs, "next_cursor": next_cursor}

    except Exception as e:
        print(f"Keyset Query Failed: {e}")
        # Re-raise the exception so the caller (the API route) knows it failed
        raise e

def get_alerts_keyset(limit=50, cursor=None, filters=None):
    """
    High-Performance Alert Fetcher.
    Targets the 'alerts' table using (timestamp, alert_id) for seeking.
    """
    pool = get_db()
    
    # 1. Parse the cursor
    # We reuse the same serializer since the data types (datetime, string) match
    cursor_ts, cursor_id = deserialize_cursor(cursor)

    # 2. Base Query
    sql = """
        SELECT timestamp, alert_id, source_ip, destination_ip, 
               signature, severity, details
        FROM alerts
        WHERE 1=1
    """
    params = {}

    # 3. Apply Filters
    if filters:
        if filters.get('ip'):
            sql += " AND (source_ip = %(ip)s OR destination_ip = %(ip)s)"
            params['ip'] = filters['ip']
        if filters.get('severity'):
            sql += " AND severity = %(severity)s"
            params['severity'] = filters['severity']
    
    # 4. Apply Seek Logic
    if cursor_ts and cursor_id:
        sql += " AND (timestamp, alert_id) < (%(cursor_ts)s, %(cursor_id)s)"
        params['cursor_ts'] = cursor_ts
        params['cursor_id'] = cursor_id

    # 5. Order and Limit
    sql += " ORDER BY timestamp DESC, alert_id DESC LIMIT %(limit)s"
    params['limit'] = limit + 1

    alerts = []
    next_cursor = None

    try:
        with pool.connect() as conn:
            raw_conn = conn.connection
            cur = raw_conn.cursor(cursor_factory=RealDictCursor)
            try:
                cur.execute(sql, params)
                rows = cur.fetchall()
                
                for row in rows:
                    # Convert to dict and format timestamp
                    alert = dict(row)
                    if alert.get('timestamp'):
                        alert['timestamp'] = alert['timestamp'].isoformat()
                    alerts.append(alert)
            finally:
                cur.close()

        # 6. Handle Pagination
        if len(alerts) > limit:
            alerts.pop() # Remove extra row
            
            # Create cursor from the last real row
            # Note: We must use the raw datetime object from the DB row, not the string we just made
            # But since we didn't keep the raw rows separately, we can re-parse or just use the string
            # The serializer handles strings fine now.
            last_row = alerts[-1]
            next_cursor = serialize_cursor(last_row['timestamp'], last_row['alert_id'])

        return {"logs": alerts, "next_cursor": next_cursor}

    except Exception as e:
        print(f"Alert Query Failed: {e}")
        raise e