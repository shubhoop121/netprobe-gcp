# /apps/api/app/security.py
import logging
import sqlalchemy
from flask import Blueprint, jsonify, request
from .db import get_db

logger = logging.getLogger(__name__)
bp = Blueprint('security', __name__, url_prefix='/api/v1/actions')

@bp.route('/block-ip', methods=['POST'])
def block_ip():
    """
    Writes the IP to the 'blocked_ips' table.
    Matches the 1_schema.sql file.
    """
    logger.info("--- POST /api/v1/actions/block-ip ---")
    
    data = request.json
    ip_to_block = data.get("ip")
    reason = data.get("reason", "Blocked by analyst via API")
    blocked_by = data.get("user", "local-admin@netprobe.com") # Get this from auth later
    
    if not ip_to_block:
        logger.error("--- block-ip: 'ip' field missing from request body. ---")
        return jsonify(error="Missing 'ip' in request body"), 400

    # FIX: This INSERT matches your new schema
    query = sqlalchemy.text(
        """
        INSERT INTO blocked_ips (ip_address, blocked_by, reason, active)
        VALUES (:ip, :user, :reason, TRUE)
        ON CONFLICT (ip_address) DO UPDATE SET
            blocked_at = NOW(),
            blocked_by = :user,
            reason = :reason,
            active = TRUE;
        """
    )
    
    try:
        db = get_db()
        with db.connect() as conn:
            conn.execute(query, {
                "ip": ip_to_block, 
                "user": blocked_by, 
                "reason": reason
            })
            conn.commit() # Commit the INSERT
            
        logger.info(f"--- LOCALLY BLOCKED IP: {ip_to_block} ---")
        
        return jsonify({
            "status": "blocking",
            "ip_blocked": ip_to_block,
            "reason": reason
        }), 202

    except Exception as e:
        logger.error(f"--- /block-ip: Failed to write to blocked_ips table: {e}", exc_info=True)
        return jsonify(error=f"Database write failed: {str(e)}"), 500