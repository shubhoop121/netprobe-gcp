# /apps/api/app/security.py
import logging
import sqlalchemy
from flask import Blueprint, jsonify, request
from .db import get_db
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)
bp = Blueprint('security', __name__, url_prefix='/api/v1/actions') # <-- Note the new path

@bp.route('/block-ip', methods=['POST'])
def block_ip():
    """
    This is the new "Block IP" logic.
    It writes the IP to the 'blocked_ips' table with an expiry time.
    This replaces the old mock function [cite: 1319, 1370-1372].
    """
    logger.info("--- POST /api/v1/actions/block-ip ---")
    
    data = request.json
    ip_to_block = data.get("ip")
    # Default block duration is 1 hour (3600 seconds)
    duration_sec = int(data.get("duration_sec", 3600)) 
    
    if not ip_to_block:
        logger.error("--- block-ip: 'ip' field missing from request body. ---")
        return jsonify(error="Missing 'ip' in request body"), 400

    # This implements the application-layer expiry logic [cite: 1319]
    expiry_time = datetime.now() + timedelta(seconds=duration_sec)
    
    query = sqlalchemy.text(
        """
        INSERT INTO blocked_ips (ip_address, block_timestamp, expiry_timestamp)
        VALUES (:ip, NOW(), :expiry)
        ON CONFLICT (ip_address) DO UPDATE SET
            block_timestamp = NOW(),
            expiry_timestamp = :expiry,
            unblocked_status = false
        """
    )
    
    try:
        db = get_db()
        with db.connect() as conn:
            conn.execute(query, {"ip": ip_to_block, "expiry": expiry_time})
            conn.commit() # This is an INSERT, so we must commit
            
        logger.info(f"--- LOCALLY BLOCKED IP: {ip_to_block} until {expiry_time.isoformat()} ---")
        
        return jsonify({
            "status": "blocking",
            "ip_blocked": ip_to_block,
            "expires_at": expiry_time.isoformat()
        }), 202

    except Exception as e:
        logger.error(f"--- /block-ip: Failed to write to blocked_ips table: {e}", exc_info=True)
        return jsonify(error=f"Database write failed: {str(e)}"), 500