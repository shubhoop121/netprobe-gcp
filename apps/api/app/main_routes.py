# /apps/api/app/main_routes.py
import logging
import sqlalchemy
import base64
import json
from flask import Blueprint, jsonify, request
from .db import get_db, get_logs_keyset, get_alerts_keyset

logger = logging.getLogger(__name__)
bp = Blueprint('main', __name__, url_prefix='/v1') # Prefix is /v1 (Proxy handles /api)

def _serialize_row(row):
    """ Helper to convert a SQLAlchemy row to a JSON-friendly dict """
    d = dict(row)
    for key, value in d.items():
        if hasattr(value, 'isoformat'): # Converts datetimes
            d[key] = value.isoformat()
        elif hasattr(value, 'addr'): # Converts INET addresses
            d[key] = str(value)
    return d

# --- DASHBOARD STATS ---
@bp.route('/stats', methods=['GET'])
def get_stats():
    logger.info("--- GET /api/v1/stats ---")
    try:
        pool = get_db()
        with pool.connect() as conn:
            # Helper for scalar counts
            def count(table):
                return conn.execute(sqlalchemy.text(f"SELECT COUNT(*) FROM {table}")).scalar()

            total_conns = count("connections")
            total_alerts = count("alerts")
            total_devices = count("devices")
            blocked_ips = conn.execute(sqlalchemy.text(
                "SELECT COUNT(*) FROM blocked_ips WHERE active = TRUE"
            )).scalar()

        return jsonify({
            "total_connections": total_conns,
            "total_alerts": total_alerts,
            "ips_blocked_now": blocked_ips,
            "devices_tracked": total_devices
        }), 200
    except Exception as e:
        logger.error(f"Stats failed: {e}", exc_info=True)
        return jsonify(error=str(e)), 500

# --- LOG VIEWER (Keyset Pagination) ---
@bp.route('/logs/connections', methods=['GET'])
def get_connections():
    logger.info("--- GET /api/v1/logs/connections ---")
    try:
        cursor = request.args.get('cursor')
        limit = int(request.args.get('limit', 50))
        if limit > 1000: limit = 1000

        filters = {}
        if request.args.get('source_ip'):
            filters['ip'] = request.args.get('source_ip')
        if request.args.get('service'):
            filters['service'] = request.args.get('service')

        # Call the db.py helper
        result = get_logs_keyset(limit=limit, cursor=cursor, filters=filters)
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Connection logs failed: {e}", exc_info=True)
        return jsonify(error="Failed to fetch logs"), 500

@bp.route('/logs/alerts', methods=['GET'])
def get_alerts():
    """
    Fetches paginated Suricata alerts.
    """
    logger.info("--- GET /api/v1/logs/alerts ---")
    
    try:
        # 1. Extract Params
        cursor = request.args.get('cursor')
        limit = int(request.args.get('limit', 50))
        if limit > 1000: limit = 1000
        
        filters = {}
        if request.args.get('source_ip'):
            filters['ip'] = request.args.get('source_ip')
        if request.args.get('severity'):
            filters['severity'] = request.args.get('severity')

        # 2. Call the DB Engine
        result = get_alerts_keyset(limit=limit, cursor=cursor, filters=filters)
        
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"Alert fetch failed: {e}", exc_info=True)
        return jsonify(error="Failed to fetch alerts"), 500

# --- DEVICE INVENTORY (The Missing Endpoint) ---
@bp.route('/devices', methods=['GET'])
def get_devices():
    """
    Returns the Device Inventory with fingerprints.
    Matches the new schema (device_uuid, primary_mac).
    """
    logger.info("--- GET /api/v1/devices ---")
    try:
        pool = get_db()
        with pool.connect() as conn:
            # Join devices with their fingerprints
            # We use json_agg to bundle fingerprints into a list for each device
            query = sqlalchemy.text("""
                SELECT 
                    d.device_uuid, d.primary_mac, d.current_hostname, 
                    d.vendor_oui, d.last_seen, d.client_id_opt61,
                    json_agg(
                        json_build_object('type', f.fingerprint_type, 'value', f.fingerprint_value)
                    ) as fingerprints
                FROM devices d
                LEFT JOIN device_fingerprints f ON d.device_uuid = f.device_uuid
                GROUP BY d.device_uuid
            """)
            
            # Use the raw connection to get a RealDictCursor for safety
            # (Or just use mappings if sqlalchemy version allows)
            result = conn.execute(query)
            
            devices = []
            for row in result:
                d = row._asdict()
                
                # Handle null fingerprints (json_agg returns [null] if no match)
                if d['fingerprints'] == [None]: 
                    d['fingerprints'] = []
                
                # Serialize UUID and Datetime for JSON
                d['device_uuid'] = str(d['device_uuid'])
                d['last_seen'] = d['last_seen'].isoformat() if d['last_seen'] else None
                
                devices.append(d)
                
            return jsonify({"devices": devices}), 200
    except Exception as e:
        logger.error(f"Device fetch failed: {e}", exc_info=True)
        return jsonify(error=str(e)), 500