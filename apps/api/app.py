import os
import sys
import logging
from flask import Flask, jsonify
from google.cloud import secretmanager
from flask_cors import CORS  # <-- 1. IMPORT
from google.cloud import secretmanager
import sqlalchemy
from dotenv import load_dotenv
app = Flask(__name__)
load_dotenv() # Load the .env file
CORS(app, resources={r"/*": {"origins": "http://localhost:3000"}})

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

# --- Configuration ---
DB_USER = os.environ.get("DB_USER", "netprobe_user")
PROJECT_ID = os.environ.get("PROJECT_ID", "netprobe-473119")
DB_NAME = os.environ.get("DB_NAME", "netprobe_logs")
DB_HOST = os.environ.get("DB_HOST") 

db = None

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

@app.before_request
def init_db():
    """Initializes the database connection pool before each request."""
    global db
    if not db:
        logger.info("--- 'db' object is None. Attempting to initialize connection pool... ---")
        try:
            db = init_connection_pool()
        except Exception as e:
            logger.error(f"!!! CRITICAL: Failed to initialize database connection: {e}", exc_info=True)
            db = None

@app.route("/")
def index():
    """Provides a simple health check."""
    logger.info("--- GET / (Health Check) ---")
    return jsonify(status="ok", service="NetProbe API")

@app.route("/ping-db")
def ping_db():
    """Tests the database connection."""
    logger.info("--- GET /ping-db ---")
    if not db:
        logger.error("--- /ping-db: Failing request because 'db' object is None. ---")
        return jsonify(error="Database connection not initialized"), 500
    
    try:
        logger.info("--- /ping-db: Pinging database with 'SELECT 1' ---")
        with db.connect() as conn:
            result = conn.execute(sqlalchemy.text("SELECT 1")).scalar()
            if result == 1:
                logger.info("--- /ping-db: Database ping successful. ---")
                return jsonify(status="ok", message="Database connection successful")
            else:
                logger.error(f"--- /ping-db: 'SELECT 1' returned '{result}', not 1. ---")
                return jsonify(status="error", message="Database connection failed"), 500
    except Exception as e:
        logger.error(f"--- /ping-db: Database query failed with exception: {e}", exc_info=True)
        return jsonify(status="error", message=f"Database query failed: {str(e)}"), 500

# --- NEWLY IMPLEMENTED ENDPOINTS ---

@app.route("/api/connections/latest")
def get_latest_connections():
    """
    Fetches the 100 most recent Zeek connection logs from the database.
    """
    logger.info("--- GET /api/connections/latest ---")
    if not db:
        logger.error("--- /api/connections/latest: Failing request because 'db' object is None. ---")
        return jsonify(error="Database connection not initialized"), 500

    try:
        with db.connect() as conn:
            # Query for the 100 most recent logs
            query = sqlalchemy.text("SELECT * FROM connections ORDER BY ts DESC LIMIT 100")
            result = conn.execute(query)
            
            # Convert the database rows into a list of dictionaries
            # ._asdict() is a clean way to convert a row to a JSON-friendly format
            connections = [row._asdict() for row in result]
            
            # Convert timestamp and IP objects to strings for JSON
            for conn in connections:
                conn['ts'] = conn['ts'].isoformat() if conn.get('ts') else None
                conn['source_ip'] = str(conn['source_ip']) if conn.get('source_ip') else None
                conn['destination_ip'] = str(conn['destination_ip']) if conn.get('destination_ip') else None

            return jsonify(connections), 200
            
    except Exception as e:
        logger.error(f"--- /api/connections/latest: Database query failed: {e}", exc_info=True)
        return jsonify(error=f"Database query failed: {str(e)}"), 500

@app.route("/api/alerts/latest")
def get_latest_alerts():
    """
    Fetches the 50 most recent Suricata alerts from the database.
    (Assumes you will create an 'alerts' table for Suricata logs).
    """
    logger.info("--- GET /api/alerts/latest ---")
    if not db:
        logger.error("--- /api/alerts/latest: Failing request because 'db' object is None. ---")
        return jsonify(error="Database connection not initialized"), 500

    # NOTE: This assumes you have a second log shipper for Suricata
    # that populates an 'alerts' table.
    
    # Placeholder query:
    mock_alerts = [
        {"ts": "2025-11-03T18:01:00", "signature": "ET SCAN Nmap Scan (Mock Data)", "src_ip": "1.2.3.4", "dest_ip": "10.0.2.5"}
    ]
    return jsonify(mock_alerts), 200
    
    # --- When your 'alerts' table is ready, use this code: ---
    # try:
    #     with db.connect() as conn:
    #         query = sqlalchemy.text("SELECT * FROM alerts ORDER BY ts DESC LIMIT 50")
    #         result = conn.execute(query)
    #         alerts = [row._asdict() for row in result]
            
    #         # Convert timestamp and IP objects to strings
    #         for alert in alerts:
    #             alert['ts'] = alert['ts'].isoformat() if alert.get('ts') else None
    #             alert['src_ip'] = str(alert['src_ip']) if alert.get('src_ip') else None
    #             alert['dest_ip'] = str(alert['dest_ip']) if alert.get('dest_ip') else None
                
    #         return jsonify(alerts), 200
    # except Exception as e:
    #     logger.error(f"--- /api/alerts/latest: Database query failed: {e}", exc_info=True)
    #     return jsonify(error=f"Database query failed: {str(e)}"), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))