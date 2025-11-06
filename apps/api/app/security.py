from flask import Blueprint, jsonify, request
from .db import get_db
# from google.cloud import compute_v1 (import your armor logic)

bp = Blueprint('security', __name__, url_prefix='/api/security')

@bp.route('/block-ip', methods=['POST'])
def block_ip():
    db = get_db()
    if not db:
        return jsonify(error="Database connection not initialized"), 500
        
    ip_to_block = request.json.get("ip")
    # (Your Cloud Armor logic goes here)
    return jsonify(status="ok", message=f"Block rule for {ip_to_block} added."), 202