# /apps/api/app/db.py
import os
import sqlalchemy
import logging
from google.cloud import secretmanager

# Get the logger from the app
logger = logging.getLogger(__name__)

# This will hold our single, global connection pool
db = None

def get_db_password():
    """
    Fetches the database password.
    Kept the 'Old Code' version because it has better logging steps.
    """
    db_pass = os.environ.get("DB_PASSWORD")
    if db_pass:
        logger.info("--- Found DB_PASSWORD in environment variable (local dev) ---")
        return db_pass

    logger.info("--- DB_PASSWORD env var not set. Fetching from Secret Manager... ---")
    PROJECT_ID = os.environ.get("PROJECT_ID", "netprobe-473119")
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
    """
    Initializes a connection pool for Cloud SQL.
    Kept the 'Old Code' settings (max_overflow, timeout) for better production stability.
    """
    DB_HOST = os.environ.get("DB_HOST")
    DB_USER = os.environ.get("DB_USER", "netprobe_user")
    DB_NAME = os.environ.get("DB_NAME", "netprobe_logs")
    
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
        max_overflow=2,  # Kept from old code
        pool_timeout=30, # Kept from old code
        pool_recycle=1800,
    )
    logger.info("--- Connection pool created successfully. ---")
    return pool

def get_db():
    """
    Returns the 'db' connection pool, initializing it if needed.
    FIX APPLIED: Removed the try/except block. If init fails, we want it to raise 
    the error immediately rather than returning None.
    """
    global db
    if db is None:
        logger.info("--- 'db' object is None. Attempting to initialize connection pool... ---")
        # We do NOT wrap this in try/except anymore. 
        # If this fails, the app should crash loudly so we know why.
        db = init_connection_pool()
        
    return db

def init_app(app):
    """
    Called by the factory to initialize the db pool.
    Kept from old code to ensure DB is ready before requests.
    """
    @app.before_request
    def initialize_database():
        get_db()