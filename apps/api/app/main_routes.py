# /apps/api/app/main_routes.py
import logging
import sqlalchemy
from flask import Blueprint, jsonify
from .db import get_db # <-- Correct relative import

logger = logging.getLogger(__name__)
bp = Blueprint('main', __name__, url_prefix='/api')



@bp.route('/connections/latest')
def get_latest_connections():
    logger.info("--- GET /api/connections/latest ---")
    db = get_db()
    if not db:
        return jsonify(error="Database connection not initialized"), 500
    
    try:
        with db.connect() as conn:
            query = sqlalchemy.text("SELECT * FROM connections ORDER BY ts DESC LIMIT 100")
            result = conn.execute(query)
            
            connections = [row._asdict() for row in result]
            
            for conn_row in connections:
                conn_row['ts'] = conn_row['ts'].isoformat() if conn_row.get('ts') else None
                conn_row['source_ip'] = str(conn_row['source_ip']) if conn_row.get('source_ip') else None
                conn_row['destination_ip'] = str(conn_row['destination_ip']) if conn_row.get('destination_ip') else None

            return jsonify(connections), 200
            
    except Exception as e:
        logger.error(f"--- /api/connections/latest: Database query failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500

@bp.route('/alerts/latest')
def get_latest_alerts():
    # (Your alerts logic here)
    mock_alerts = [{"ts": "2025-11-03T18:01:00", "signature": "ET SCAN Nmap Scan (Mock Data)"}]
    return jsonify(mock_alerts), 200