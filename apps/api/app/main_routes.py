# apps/api/app/main_routes.py
import logging
import sqlalchemy
from flask import Blueprint, jsonify
from .db import get_db
from flask import Blueprint, jsonify, request
from .db import get_db, get_logs_keyset

logger = logging.getLogger(__name__)
bp = Blueprint('main', __name__, url_prefix='/v1')

@bp.route('/stats', methods=['GET'])
def get_stats():
    """
    Gets high-level stats for the main dashboard.
    """
    logger.info("--- GET /api/v1/stats ---")
    
    try:
        pool = get_db()
        with pool.connect() as conn:
            # Helper to run scalar queries
            def count(table):
                return conn.execute(sqlalchemy.text(f"SELECT COUNT(*) FROM {table}")).scalar()

            # Run specific queries
            total_conns = count("connections")
            total_alerts = count("alerts")
            total_devices = count("devices")
            
            # Count currently blocked IPs
            blocked_ips = conn.execute(sqlalchemy.text(
                "SELECT COUNT(*) FROM blocked_ips WHERE active = TRUE"
            )).scalar()

        stats = {
            "total_connections": total_conns,
            "total_alerts": total_alerts,
            "ips_blocked_now": blocked_ips,
            "devices_tracked": total_devices
        }
        
        return jsonify(stats), 200

    except Exception as e:
        logger.error(f"--- /api/v1/stats Failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500

# ... (You can add the /logs and /devices endpoints here later) ...

@bp.route('/logs/connections', methods=['GET'])
def get_connections():
    """
    Fetches paginated connection logs using Keyset Pagination.
    Query Params:
      - limit: (int) Number of rows to fetch (default 50)
      - cursor: (str) The 'next_cursor' string from the previous response
      - ip: (str) Filter by IP address (source or dest)
    """
    logger.info("--- GET /api/v1/logs/connections ---")
    
    try:
        # 1. Extract Parameters
        cursor = request.args.get('cursor')
        limit = int(request.args.get('limit', 50))
        
        # Simple security check on limit
        if limit > 1000: limit = 1000 

        # Extract filters
        filters = {}
        if request.args.get('ip'):
            filters['ip'] = request.args.get('ip')

        # 2. Call the DB Engine
        result = get_logs_keyset(limit=limit, cursor=cursor, filters=filters)
        
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"Log fetch failed: {e}", exc_info=True)
        return jsonify(error="Failed to fetch logs"), 500