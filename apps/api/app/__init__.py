# /apps/api/app/__init__.py
import os
import logging
import sys
from flask import Flask, jsonify
from flask_cors import CORS
from . import db
import sqlalchemy
from .db import get_db

def create_app():
    # --- Set up a loud logger (Kept from old code for visibility) ---
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)
    stderr_handler = logging.StreamHandler(sys.stderr)
    stderr_handler.setLevel(logging.DEBUG)
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    stderr_handler.setFormatter(formatter)
    
    # Avoid adding handlers multiple times if factory is called again
    if not logger.hasHandlers():
        logger.addHandler(stderr_handler)
    # --- End of logger setup ---
    
    app = Flask(__name__)
    
    # 2. Setup CORS
    # Kept strict localhost:3000 from old code for safety.
    # If using a proxy in prod, this might not strictly be needed, but it doesn't hurt.
    CORS(app, resources={r"/*": {"origins": "http://localhost:3000"}})

    # 3. Initialize Extensions
    # This calls the init_app in db.py we just saved
    db.init_app(app)

    # 4. Register Blueprints
    from . import main_routes
    from . import security
    
    app.register_blueprint(main_routes.bp)
    app.register_blueprint(security.bp)
    
    # --- ROOT-LEVEL ROUTES ---

    @app.route("/")
    def index():
        """Provides a simple health check."""
        logger.info("--- GET / (Health Check) ---")
        # Updated response format to match new code's JSON style
        return jsonify(status="ok", service="NetProbe API")

    @app.route("/ping-db")
    def ping_db():
        """Tests the database connection."""
        logger.info("--- GET /ping-db ---")
        
        try:
            # Note: get_db() returns the ENGINE/POOL
            db_conn = get_db() 
            
            # Since we removed the None check in db.py, this might raise if init failed,
            # which is good - it goes to the 'except' block below.
            
            logger.info("--- /ping-db: Pinging database with 'SELECT 1' ---")
            
            # We must connect explicitly from the pool
            with db_conn.connect() as conn:
                # Use sqlalchemy.text for safety
                result = conn.execute(sqlalchemy.text("SELECT 1")).scalar()
            
            if result == 1:
                return jsonify(status="ok", message="Database connection successful")
            else:
                return jsonify(status="error", message="Database ping failed (unexpected result)"), 500

        except Exception as e:
            logger.error(f"--- /ping-db: Database query failed: {e}", exc_info=True)
            return jsonify(status="error", message=f"Database query failed: {str(e)}"), 500

    # This MUST be the last line of the create_app function
    return app