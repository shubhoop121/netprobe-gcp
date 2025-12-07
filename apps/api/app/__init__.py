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
    CORS(app) 

    # 3. Initialize Extensions
    with app.app_context():
        try:
            # Eagerly check DB connection on startup (optional)
            pass
        except Exception as e:
            logger.warning(f"DB Connection check failed on startup: {e}")

    # 4. Register Blueprints
    from . import main_routes
    # REMOVED: from . import security  <-- DELETED
    
    app.register_blueprint(main_routes.bp)
    # REMOVED: app.register_blueprint(security.bp) <-- DELETED

    # 5. Root Health Check
    @app.route("/")
    def index():
        return jsonify(status="ok", service="NetProbe API")

    # 6. DB Ping Endpoint
    @app.route("/ping-db")
    def ping_db():
        try:
            pool = db.get_db()
            with pool.connect() as conn:
                conn.execute(sqlalchemy.text("SELECT 1"))
            return jsonify(status="ok", message="Database connection successful")
        except Exception as e:
            logger.error(f"DB Ping Failed: {e}")
            return jsonify(status="error", message=str(e)), 500

    return app