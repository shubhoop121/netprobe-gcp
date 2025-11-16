# /apps/api/app/main_routes.py
import logging
import sqlalchemy
import base64
import json
from flask import Blueprint, jsonify, request
from .db import get_db

logger = logging.getLogger(__name__)
bp = Blueprint('main', __name__, url_prefix='/api/v1')

def _serialize_row(row):
    """ Helper to convert a SQLAlchemy row to a JSON-friendly dict """
    d = row._asdict()
    for key, value in d.items():
        if hasattr(value, 'isoformat'): # Converts datetimes
            d[key] = value.isoformat()
        elif hasattr(value, 'addr'): # Converts INET addresses
            d[key] = str(value)
    return d

@bp.route('/logs/connections', methods=['GET'])
def get_connections():
    logger.info("--- GET /api/v1/logs/connections ---")
    
    # --- 1. Get query parameters ---
    cursor_str = request.args.get('cursor')
    limit = int(request.args.get('limit', 50))
    filter_ip = request.args.get('source_ip') # New filter param
    
    # --- 2. Build the query dynamically ---
    query_str = "SELECT ts, uid, source_ip, source_port, destination_ip, destination_port, proto, service FROM connections"
    params = {}
    
    # Use a WHERE clause
    # We will build a list of "where" conditions
    where_clauses = []

    if cursor_str:
        try:
            last_ts, last_uid = json.loads(base64.urlsafe_b64decode(cursor_str))
            # Add keyset pagination as the first "where"
            where_clauses.append("(ts, uid) < (:last_ts, :last_uid)")
            params["last_ts"] = last_ts
            params["last_uid"] = last_uid
        except:
            return jsonify(error="Invalid cursor format"), 400
    
    # --- 3. Add the new filter ---
    if filter_ip:
        where_clauses.append("source_ip = :filter_ip")
        params["filter_ip"] = filter_ip
    
    # --- 4. Assemble the full query ---
    if where_clauses:
        query_str += " WHERE " + " AND ".join(where_clauses)
    
    query_str += " ORDER BY ts DESC, uid DESC LIMIT :limit"
    params["limit"] = limit
    
    logger.info(f"Executing query: {query_str}")
    logger.info(f"With params: {params}")

    try:
        db = get_db()
        with db.connect() as conn:
            query = sqlalchemy.text(query_str)
            result = conn.execute(query, params)
            
            logs = [_serialize_row(row) for row in result]
            next_cursor = None
            
            if logs:
                last_log = logs[-1]
                # FIX: Create cursor from 'ts' and 'uid'
                cursor_data = json.dumps([last_log['ts'], last_log['uid']])
                next_cursor = base64.urlsafe_b64encode(cursor_data.encode('utf-8')).decode('utf-8')

            return jsonify({
                "logs": logs,
                "next_cursor": next_cursor
            }), 200
            
    except Exception as e:
        logger.error(f"Database query failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500

@bp.route('/logs/alerts', methods=['GET'])
def get_alerts():
    """
    Fetches paginated Suricata alerts.
    """
    logger.info("--- GET /api/v1/logs/alerts ---")
    
    cursor_str = request.args.get('cursor')
    limit = int(request.args.get('limit', 50))
    
    # FIX: Querying the correct table 'alerts'
    query_str = "SELECT timestamp, alert_id, source_ip, destination_ip, signature, severity FROM alerts"
    params = {}

    if cursor_str:
        try:
            # FIX: Using correct pagination columns 'timestamp' and 'alert_id'
            last_ts, last_id = json.loads(base64.urlsafe_b64decode(cursor_str))
            query_str += " WHERE (timestamp, alert_id) < (:last_ts, :last_id)"
            params = {"last_ts": last_ts, "last_id": last_id}
        except:
            return jsonify(error="Invalid cursor format"), 400
    
    # FIX: Using correct pagination columns 'timestamp' and 'alert_id'
    query_str += " ORDER BY timestamp DESC, alert_id DESC LIMIT :limit"
    params["limit"] = limit
    
    try:
        db = get_db()
        with db.connect() as conn:
            query = sqlalchemy.text(query_str)
            result = conn.execute(query, params)
            
            logs = [_serialize_row(row) for row in result]
            next_cursor = None
            
            if logs:
                last_log = logs[-1]
                # FIX: Create cursor from 'timestamp' and 'alert_id'
                cursor_data = json.dumps([last_log['timestamp'], last_log['alert_id']])
                next_cursor = base64.urlsafe_b64encode(cursor_data.encode('utf-8')).decode('utf-8')
                
            return jsonify({ "logs": logs, "next_cursor": next_cursor }), 200
            
    except Exception as e:
        logger.error(f"Database query failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500


# /apps/api/app/main_routes.py

@bp.route('/devices', methods=['GET'])
def get_devices():
    """
    Reads from the devices and fingerprints tables.
    """
    logger.info("--- GET /api/v1/devices ---")
    
    # FIX: We must use aliases (e.g., dev_last_seen) because 'last_seen'
    # is in both tables, which causes ambiguity.
    query = sqlalchemy.text("""
        SELECT 
            d.device_id, d.mac_address, d.first_seen, d.last_seen AS dev_last_seen, d.friendly_name,
            f.fingerprint_type, f.fingerprint_value, f.last_seen AS f_last_seen
        FROM devices d
        LEFT JOIN device_fingerprints f ON d.device_id = f.device_id;
    """)
    
    try:
        db = get_db()
        with db.connect() as conn:
            result = conn.execute(query)
            devices = {}
            for row in result:
                d = row._asdict()
                dev_id = d['device_id']
                
                if dev_id not in devices:
                    devices[dev_id] = {
                        "device_id": dev_id,
                        "mac_address": str(d['mac_address']),
                        "first_seen": d['first_seen'].isoformat() if d.get('first_seen') else None,
                        # FIX: Use the correct aliased column 'dev_last_seen'
                        "last_seen": d['dev_last_seen'].isoformat() if d.get('dev_last_seen') else None,
                        "friendly_name": d['friendly_name'],
                        "fingerprints": []
                    }
                
                if d.get('fingerprint_value'):
                    devices[dev_id]['fingerprints'].append({
                        "type": d['fingerprint_type'],
                        "value": d['fingerprint_value'],
                        # FIX: Use the correct aliased column 'f_last_seen'
                        "last_seen": d['f_last_seen'].isoformat() if d.get('f_last_seen') else None
                    })
            
        return jsonify({"devices": list(devices.values())})
    except Exception as e:
        logger.error(f"Database query failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500
    
    # ... (keep all existing imports: logging, sqlalchemy, base64, json, etc.)

# ... (keep your existing 'bp' Blueprint definition) ...
# bp = Blueprint('main', __name__, url_prefix='/api/v1')

# ... (keep your existing 'get_connections', 'get_alerts', and 'get_devices' functions) ...


# --- ADD THIS NEW FUNCTION ---

@bp.route('/stats', methods=['GET'])
def get_stats():
    """
    Gets high-level stats for the main dashboard.
    This runs multiple fast, aggregate queries [cite: 3451-3453].
    """
    logger.info("--- GET /api/v1/stats ---")
    
    # Define the aggregate queries
    query_total_conns = sqlalchemy.text("SELECT COUNT(*) FROM connections;")
    query_alerts_total = sqlalchemy.text("SELECT COUNT(*) FROM alerts;")
    query_blocked_ips = sqlalchemy.text(
        "SELECT COUNT(*) FROM blocked_ips WHERE active = TRUE;"
    )
    query_devices = sqlalchemy.text("SELECT COUNT(*) FROM devices;")

    try:
        db = get_db()
        with db.connect() as conn:
            # Execute all queries
            total_conns = conn.execute(query_total_conns).scalar()
            total_alerts = conn.execute(query_alerts_total).scalar()
            blocked_ips = conn.execute(query_blocked_ips).scalar()
            total_devices = conn.execute(query_devices).scalar()

        # Build the JSON response
        stats = {
            "total_connections": total_conns,
            "total_alerts": total_alerts,
            "ips_blocked_now": blocked_ips,
            "devices_tracked": total_devices
        }
        
        return jsonify(stats), 200

    except Exception as e:
        logger.error(f"--- /api/v1/stats: Database query failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500