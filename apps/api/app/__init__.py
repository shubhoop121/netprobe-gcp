# apps/api/app/__init__.py
import logging
import sys
import os
from flask import Flask, jsonify
from flask_cors import CORS
import sqlalchemy
from . import db

def create_app():
    # 1. Setup Logging
    logging.basicConfig(
        stream=sys.stdout, 
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    app = Flask(__name__)

    # 2. Setup CORS
    # In production, we don't strictly need this because of the Proxy,
    # but it helps if you ever hit the API directly during debugging.
    CORS(app) 

    # 3. Initialize Extensions
    # (We don't have a complex db.init_app(app) yet, but we place the hook here)
    with app.app_context():
        try:
            # Eagerly check DB connection on startup (optional but good for debugging)
            # db.get_db() 
            pass
        except Exception as e:
            logger.warning(f"DB Connection check failed on startup: {e}")

    # 4. Register Blueprints
    from . import main_routes
    from . import security
    
    app.register_blueprint(main_routes.bp)
    app.register_blueprint(security.bp)

    # 5. Root Health Check
    @app.route("/")
    def index():
        return jsonify(status="ok", service="NetProbe API")

    # 6. DB Ping Endpoint (Moved from old app.py)
    @app.route("/ping-db")
    def ping_db():
        try:
            conn = db.get_db()
            # Use a text query for simple check
            # Note: In the new structure, get_db returns the ENGINE/POOL, not a connection.
            # We must connect explicitly.
            with conn.connect() as c:
                # sqlalchemy < 2.0 usage:
                c.execute(sqlalchemy.text("SELECT 1"))
            return jsonify(status="ok", message="Database connection successful")
        except Exception as e:
            logger.error(f"DB Ping Failed: {e}")
            return jsonify(status="error", message=str(e)), 500

    return app