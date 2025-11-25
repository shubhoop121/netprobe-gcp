# apps/api/app/main_routes.py
import logging
import sqlalchemy
from flask import Blueprint, jsonify
from .db import get_db

logger = logging.getLogger(__name__)
bp = Blueprint('main', __name__, url_prefix='/api/v1')

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