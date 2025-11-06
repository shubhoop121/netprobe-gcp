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
    # --- Set up a loud logger ---
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
    
    # Allow requests from your local React app (http://localhost:3000)
    CORS(app, resources={r"/*": {"origins": "http://localhost:3000"}})

    # Initialize the database connection pool
    db.init_app(app)

    # Import and register your routes (endpoints)
    from . import main_routes
    from . import security
    
    app.register_blueprint(main_routes.bp)
    app.register_blueprint(security.bp)
    
    # --- ROOT-LEVEL ROUTES (MOVED INSIDE) ---

    @app.route("/")
    def index():
        """Provides a simple health check."""
        logger.info("--- GET / (Health Check) ---")
        return "NetProbe API is alive!"

    @app.route("/ping-db")
    def ping_db():
        """Tests the database connection."""
        logger.info("--- GET /ping-db ---")
        db_conn = get_db() # Get the connection pool
        if not db_conn:
            logger.error("--- /ping-db: Failing request because 'db' object is None. ---")
            return jsonify(error="Database connection not initialized"), 500
        
        try:
            logger.info("--- /ping-db: Pinging database with 'SELECT 1' ---")
            with db_conn.connect() as conn:
                result = conn.execute(sqlalchemy.text("SELECT 1")).scalar()
            
            if result == 1:
                return jsonify(status="ok", message="Database connection successful")
            else:
                return jsonify(status="error", message="Database ping failed"), 500

        except Exception as e:
            logger.error(f"--- /ping-db: Database query failed: {e}", exc_info=True)
            return jsonify(status="error", message=f"Database query failed: {str(e)}"), 500

    # This MUST be the last line of the create_app function
    return app