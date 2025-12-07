import logging
import sqlalchemy
from flask import Blueprint, jsonify, request
from .db import get_db
# Ensure this helper file exists as created previously
from .cloud_armor import block_ip_in_armor 

logger = logging.getLogger(__name__)
bp = Blueprint('security', __name__, url_prefix='/api/v1/actions')

@bp.route('/block-ip', methods=['POST'])
def block_ip():
    logger.info("--- POST /api/v1/actions/block-ip ---")
    
    data = request.json
    if not data:
        return jsonify(error="Request body must be JSON"), 400

    ip_to_block = data.get("ip")
    blocked_by = data.get("user", "local-admin@netprobe.com") 
    reason = data.get("reason", "Blocked via Live Feed")
    
    if not ip_to_block:
        return jsonify(error="Missing 'ip' in request body"), 400

    # 1. Call Mock Helper
    armor_success = block_ip_in_armor(ip_to_block)

    # 2. Database Operation (FIXED FOR YOUR SCHEMA)
    # - Using 'blocked_at' (matches your schema)
    # - REMOVED 'ON CONFLICT' because your ip_address column is not UNIQUE
    query = sqlalchemy.text(
        """
        INSERT INTO blocked_ips (ip_address, blocked_by, reason, active, blocked_at)
        VALUES (:ip, :user, :reason, TRUE, NOW());
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
            conn.commit()
            
        logger.info(f"--- BLOCKED IP: {ip_to_block} ---")
        
        return jsonify({
            "status": "success",
            "message": f"IP {ip_to_block} blocked successfully.",
            "cloud_armor_synced": armor_success['status']
        }), 200

    except Exception as e:
        logger.error(f"--- /block-ip failed: {e}", exc_info=True)
        return jsonify(error=f"Database error: {str(e)}"), 500