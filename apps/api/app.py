import os
from flask import Flask, jsonify
from google.cloud import secretmanager
import sqlalchemy

app = Flask(__name__)

# --- Configuration ---
# Get configuration from environment variables
DB_USER = os.environ.get("DB_USER", "netprobe_user")
PROJECT_ID = os.environ.get("PROJECT_ID", "netprobe-473119")
DB_NAME = os.environ.get("DB_NAME", "netprobe_logs")
DB_HOST = os.environ.get("DB_HOST") # e.g., 10.x.x.x (the private IP)

# --- Database Setup ---
db = None

def get_db_password():
    """
    Fetches the database password.
    Priority:
    1. DB_PASSWORD environment variable (for local dev)
    2. Google Cloud Secret Manager (for production)
    """
    
    # 1. Check for local environment variable first
    db_pass = os.environ.get("DB_PASSWORD")
    if db_pass:
        print("--- Found DB_PASSWORD in environment variable (local dev) ---")
        return db_pass

    # 2. If not found, fall back to Secret Manager (for production)
    print("--- DB_PASSWORD env var not set. Fetching from Secret Manager (production) ---")
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/db-password/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"Error fetching secret from Secret Manager: {e}")
        return None

def init_connection_pool() -> sqlalchemy.engine.base.Engine:
    """Initializes a Unix socket connection pool for Cloud SQL."""
    if not DB_HOST:
        raise ValueError("DB_HOST environment variable is not set.")

    db_pass = get_db_password()
    if not db_pass:
        raise ValueError("Database password could not be retrieved.")

    db_uri = sqlalchemy.engine.url.URL.create(
        drivername="postgresql+psycopg2",
        username=DB_USER,
        password=db_pass,
        host=DB_HOST,
        port=5432,
        database=DB_NAME,
    )

    # Create the connection pool
    pool = sqlalchemy.create_engine(
        db_uri,
        pool_size=5,
        max_overflow=2,
        pool_timeout=30,
        pool_recycle=1800,
    )
    return pool

@app.before_request
def init_db():
    """Initializes the database connection pool before each request."""
    global db
    if not db:
        try:
            db = init_connection_pool()
        except Exception as e:
            print(f"Failed to initialize database connection: {e}")
            db = None # Keep it None so we can retry

@app.route("/")
def index():
    """Provides a simple health check."""
    return jsonify(status="ok", service="NetProbe API")

@app.route("/ping-db")
def ping_db():
    """Tests the database connection."""
    if not db:
        return jsonify(error="Database connection not initialized"), 500

    try:
        with db.connect() as conn:
            result = conn.execute(sqlalchemy.text("SELECT 1")).scalar()
            if result == 1:
                return jsonify(status="ok", message="Database connection successful")
            else:
                return jsonify(status="error", message="Database connection failed"), 500
    except Exception as e:
        return jsonify(status="error", message=f"Database query failed: {str(e)}"), 500

# --- Team can start adding new endpoints here ---

@app.route("/api/connections/latest")
def get_latest_connections():
    """EXAMPLE: Team member will implement this."""
    # 1. Check for DB connection
    # 2. Execute query: sqlalchemy.text("SELECT * FROM connections ORDER BY ts DESC LIMIT 100")
    # 3. Format results as JSON
    # 4. Return jsonify(data=...)
    return jsonify(message="Endpoint not implemented"), 501

# --- End of endpoints ---

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))