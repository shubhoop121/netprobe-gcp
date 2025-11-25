import os
import sqlalchemy
import logging
from google.cloud import secretmanager

logger = logging.getLogger(__name__)
db = None

def get_db_password():
    """Fetches password from Env (Local) or Secret Manager (Prod)."""
    if os.environ.get("DB_PASSWORD"):
        return os.environ.get("DB_PASSWORD")

    # Production Fallback
    logger.info("--- Fetching DB_PASSWORD from Secret Manager ---")
    PROJECT_ID = os.environ.get("PROJECT_ID", "netprobe-473119")
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/db-password/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        logger.error(f"!!! CRITICAL: Secret Manager failure: {e}")
        return None

def init_connection_pool():
    DB_HOST = os.environ.get("DB_HOST")
    DB_USER = os.environ.get("DB_USER", "netprobe_user")
    DB_NAME = os.environ.get("DB_NAME", "netprobe_logs")
    
    if not DB_HOST:
        raise ValueError("DB_HOST not set.")

    db_pass = get_db_password()
    if not db_pass:
        raise ValueError("DB_PASSWORD could not be retrieved.")

    db_uri = sqlalchemy.engine.url.URL.create(
        drivername="postgresql+psycopg2",
        username=DB_USER,
        password=db_pass,
        host=DB_HOST,
        port=5432,
        database=DB_NAME,
    )
    
    return sqlalchemy.create_engine(db_uri, pool_size=5, pool_recycle=1800)

def get_db():
    """Lazy init of DB pool."""
    global db
    if db is None:
        logger.info("--- Initializing DB Pool... ---")
        db = init_connection_pool()
    return db

def init_app(app):
    """Register teardown/setup hooks if needed."""
    pass