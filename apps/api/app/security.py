import logging
import sqlalchemy
from flask import Blueprint, jsonify, request
from .db import get_db
from .cloud_armor import block_ip_in_armor 

logger = logging.getLogger(__name__)
bp = Blueprint('security', __name__, url_prefix='/api/v1/actions')

@bp.route('/block-ip', methods=['POST'])
def block_ip():
    """
    Writes the IP to the 'blocked_ips' table AND updates Cloud Armor.
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

    # --- SQL Query (Matches your schema) ---
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
        # 1. NEW: Call Cloud Armor (The Shim)
        # We do this first so we don't write to DB if the actual block fails.
        armor_result = block_ip_in_armor(ip_to_block)
        logger.info(f"Cloud Armor result: {armor_result}")

        # 2. EXISTING: Write to DB
        db = get_db()
        with db.connect() as conn:
            conn.execute(query, {
                "ip": ip_to_block, 
                "user": blocked_by, 
                "reason": reason
            })
            conn.commit() # Commit the INSERT
            
        logger.info(f"--- BLOCKED IP: {ip_to_block} ---")
        
        # 3. Return Combined Status
        return jsonify({
            "status": "blocking",
            "armor_status": armor_result.get('status', 'unknown'),
            "ip_blocked": ip_to_block,
            "reason": reason
        }), 202

    except Exception as e:
        logger.error(f"--- /block-ip: Operation failed: {e}", exc_info=True)
        return jsonify(error=f"Block operation failed: {str(e)}"), 500