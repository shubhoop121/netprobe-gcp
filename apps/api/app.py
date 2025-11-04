# apps/api/app.py (Final Version)

import os
import sys
import logging
import sqlalchemy
from flask import Flask, jsonify
from google.cloud import secretmanager

# --- Set up a loud logger ---
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
stderr_handler = logging.StreamHandler(sys.stderr)
stderr_handler.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
stderr_handler.setFormatter(formatter)
logger.addHandler(stderr_handler)
# --- End of logger setup ---

app = Flask(__name__)

# --- Configuration (read at import time) ---
DB_USER = os.environ.get("DB_USER", "netprobe_user")
PROJECT_ID = os.environ.get("PROJECT_ID", "netprobe-473119")
DB_NAME = os.environ.get("DB_NAME", "netprobe_logs")
DB_HOST = os.environ.get("DB_HOST") # Injected by Cloud Run

# --- THIS IS THE FIX (Part 1) ---
# Create a global 'db' variable, but leave it as None.
# We will initialize it "lazily" on the first request.
db = None
# --- END FIX ---

def get_db_password():
    """Fetches the database password."""
    db_pass = os.environ.get("DB_PASSWORD")
    if db_pass:
        logger.info("--- Found DB_PASSWORD in environment variable (local dev) ---")
        return db_pass

    logger.info("--- DB_PASSWORD env var not set. Fetching from Secret Manager... ---")
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/db-password/versions/latest"
        response = client.access_secret_version(request={"name": name})
        password = response.payload.data.decode("UTF-8")
        logger.info("--- Successfully fetched 'db-password' from Secret Manager. ---")
        return password
    except Exception as e:
        logger.error(f"!!! CRITICAL: Error fetching secret from Secret Manager: {e}", exc_info=True)
        return None

def init_connection_pool() -> sqlalchemy.engine.base.Engine:
    """Initializes a connection pool for Cloud SQL."""
    
    if not DB_HOST:
        logger.error("!!! CRITICAL: DB_HOST environment variable is not set. Cannot initialize. ---")
        raise ValueError("DB_HOST environment variable is not set.")

    db_pass = get_db_password()
    if not db_pass:
        logger.error("!!! CRITICAL: Database password could not be retrieved. Cannot initialize. ---")
        raise ValueError("Database password could not be retrieved.")

    db_uri = sqlalchemy.engine.url.URL.create(
        drivername="postgresql+psycopg2",
        username=DB_USER,
        password=db_pass,
        host=DB_HOST,
        port=5432,
        database=DB_NAME,
    )

    logger.info(f"--- Attempting to create connection pool for user '{DB_USER}' at host '{DB_HOST}' ---")
    pool = sqlalchemy.create_engine(
        db_uri,
        pool_size=5,
        max_overflow=2,
        pool_timeout=30,
        pool_recycle=1800,
    )
    logger.info("--- Connection pool created successfully. ---")
    return pool

# --- THIS IS THE FIX (Part 2) ---
# Use a global function to get the database connection.
# This ensures init_connection_pool() is only called when a request
# actually comes in, not when the container is importing the script.
def get_db():
    global db
    if not db:
        logger.info("--- 'db' object is None. Initializing connection pool... ---")
        try:
            db = init_connection_pool()
        except Exception as e:
            logger.error(f"!!! CRITICAL: Failed to initialize database connection: {e}", exc_info=True)
            db = None # Keep it None so we can see the error
    return db
# --- END FIX ---

@app.route("/")
def index():
    """Provides a simple health check."""
    logger.info("--- GET / (Health Check) ---")
    return jsonify(status="ok", service="NetProbe API")

@app.route("/ping-db")
def ping_db():
    """Tests the database connection."""
    logger.info("--- GET /ping-db ---")
    # Use the get_db() function
    conn = get_db()
    
    if not conn:
        logger.error("--- /ping-db: Failing request because 'db' object is None. ---")
        return jsonify(error="Database connection not initialized"), 500
    
    try:
        logger.info("--- /ping-db: Pinging database with 'SELECT 1' ---")
        with conn.connect() as c:
            result = c.execute(sqlalchemy.text("SELECT 1")).scalar()
            if result == 1:
                logger.info("--- /ping-db: Database ping successful. ---")
                return jsonify(status="ok", message="Database connection successful")
            else:
                logger.error(f"--- /ping-db: 'SELECT 1' returned '{result}', not 1. ---")
                return jsonify(status="error", message="Database connection failed"), 500
    except Exception as e:
        logger.error(f"--- /ping-db: Database query failed with exception: {e}", exc_info=True)
        return jsonify(status="error", message=f"Database query failed: {str(e)}"), 500

# --- (Other endpoints like /api/connections/latest) ---

if __name__ == "__main__":
    # This part is only for local dev (python app.py)
    # Gunicorn does not run this.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))