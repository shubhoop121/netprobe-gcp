import sys
import os
import pytest
from dotenv import load_dotenv

# --- THIS IS THE FIX ---
# Add the parent directory ('apps/api/') to the Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Load .env variables BEFORE the app is created
load_dotenv() 
# --- END OF FIX ---

from app import create_app # Import app AFTER loading env

@pytest.fixture
def app():
    """Create and configure a new app instance for each test."""
    
    app = create_app()
    app.config.update({
        "TESTING": True,
    })

    yield app

@pytest.fixture
def client(app):
    """A test client for the app."""
    return app.test_client()