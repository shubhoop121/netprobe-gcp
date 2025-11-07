# /apps/api/app/main_routes.py
import logging
import sqlalchemy
import base64
import json
from flask import Blueprint, jsonify, request
from .db import get_db

logger = logging.getLogger(__name__)
bp = Blueprint('main', __name__, url_prefix='/api/v1') # <-- Note the new path

@bp.route('/logs/connections', methods=['GET'])
def get_connections():
    """
    Implements Keyset Pagination to fetch connection logs.
    This is the high-performance method required by the new plan.
    [cite: 1365-1368]
    """
    logger.info("--- GET /api/v1/logs/connections ---")
    
    # Keyset Pagination: Get the 'cursor' from the query parameters
    cursor_str = request.args.get('cursor')
    limit = int(request.args.get('limit', 50))
    
    # Base query
    query_str = "SELECT id, created_at, uid, source_ip, source_port, destination_ip, destination_port, proto FROM conn_logs"
    params = {}

    if cursor_str:
        # Decode the cursor to get the last seen timestamp and ID
        try:
            # The cursor is a (timestamp, id) tuple
            last_created_at, last_id = json.loads(base64.urlsafe_b64decode(cursor_str))
            
            # This SQL query is the core of Keyset Pagination
            query_str += " WHERE (created_at, id) < (:last_created_at, :last_id)"
            params = {"last_created_at": last_created_at, "last_id": last_id}
        except:
            return jsonify(error="Invalid cursor format"), 400
    
    # We order by time, and use ID as a tie-breaker
    query_str += " ORDER BY created_at DESC, id DESC LIMIT :limit"
    params["limit"] = limit

    try:
        db = get_db()
        with db.connect() as conn:
            query = sqlalchemy.text(query_str)
            result = conn.execute(query, params)
            
            logs = [row._asdict() for row in result]
            next_cursor = None
            
            if logs:
                # Create the cursor for the *next* page
                last_log = logs[-1]
                # The cursor value is the (created_at, id) of the last row we fetched
                cursor_data = json.dumps([last_log['created_at'].isoformat(), last_log['id']])
                next_cursor = base64.urlsafe_b64encode(cursor_data.encode('utf-8')).decode('utf-8')

            # Convert for JSON
            for log in logs:
                log['created_at'] = log['created_at'].isoformat()
                log['source_ip'] = str(log['source_ip'])
                log['destination_ip'] = str(log['destination_ip'])

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
    Fetches the 50 most recent Suricata alerts.
    (This will be implemented similarly to get_connections)
    """
    logger.info("--- GET /api/v1/logs/alerts ---")
    
    # Placeholder: The full implementation will be identical
    # to get_connections, just querying the 'alert_logs' table.
    mock_alerts = [
        {"id": 1, "created_at": "2025-11-07T12:00:00Z", "signature": "ET SCAN Nmap Scan (Mock Data)", "source_ip": "1.2.3.4"}
    ]
    return jsonify({
        "logs": mock_alerts,
        "next_cursor": "mock-cursor-for-alerts"
    }), 200

@bp.route('/devices', methods=['GET'])
def get_devices():
    """
    Reads from the pre-computed devices table.
    The complex logic is handled by a separate background job [cite: 1253-1254].
    """
    logger.info("--- GET /api/v1/devices ---")
    query = sqlalchemy.text("SELECT * FROM devices;")
    
    try:
        db = get_db()
        with db.connect() as conn:
            result = conn.execute(query)
            devices = [row._asdict() for row in result]
            
            # Convert for JSON
            for dev in devices:
                if dev.get('last_seen'):
                    dev['last_seen'] = dev['last_seen'].isoformat()
            
        return jsonify({"devices": devices})
    except Exception as e:
        logger.error(f"Database query failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500